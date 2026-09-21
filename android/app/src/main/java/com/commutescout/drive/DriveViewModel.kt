package com.commutescout.drive

import android.app.Application
import android.location.Geocoder
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewModelScope
import com.stadiamaps.ferrostar.composeui.notification.DefaultForegroundNotificationBuilder
import com.stadiamaps.ferrostar.core.AlternativeRouteProcessor
import com.stadiamaps.ferrostar.core.AndroidTtsObserver
import com.stadiamaps.ferrostar.core.CorrectiveAction
import com.stadiamaps.ferrostar.core.CustomRouteProvider
import com.stadiamaps.ferrostar.core.FerrostarSessionBuilder
import com.stadiamaps.ferrostar.core.RouteProvider
import uniffi.ferrostar.RouteAdapter
import uniffi.ferrostar.RouteRequest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import com.stadiamaps.ferrostar.core.DefaultNavigationViewModel
import com.stadiamaps.ferrostar.core.FerrostarCore
import com.stadiamaps.ferrostar.core.NavigationUiState
import com.stadiamaps.ferrostar.core.RouteDeviationHandler
import com.stadiamaps.ferrostar.core.annotation.valhalla.valhallaExtendedOSRMAnnotationPublisher
import com.stadiamaps.ferrostar.core.http.OkHttpClientProvider.Companion.toOkHttpClientProvider
import com.stadiamaps.ferrostar.core.location.NavigationLocationProvider
import com.stadiamaps.ferrostar.core.location.SimulatedLocationProvider
import com.stadiamaps.ferrostar.core.location.toAndroidLocation
import com.stadiamaps.ferrostar.core.location.toUserLocation
import com.stadiamaps.ferrostar.core.service.FerrostarForegroundServiceManager
import com.stadiamaps.ferrostar.core.withJsonOptions
import com.stadiamaps.ferrostar.googleplayservices.FusedNavigationLocationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.Locale
import uniffi.ferrostar.CourseFiltering
import uniffi.ferrostar.GeographicCoordinate
import uniffi.ferrostar.NavigationControllerConfig
import uniffi.ferrostar.Route
import uniffi.ferrostar.RouteDeviationTracking
import uniffi.ferrostar.UserLocation
import uniffi.ferrostar.Waypoint
import uniffi.ferrostar.WaypointAdvanceMode
import uniffi.ferrostar.WaypointKind
import uniffi.ferrostar.WellKnownRouteProvider
import uniffi.ferrostar.stepAdvanceDistanceEntryAndExit
import uniffi.ferrostar.stepAdvanceDistanceToEndOfStep

/** What the app is doing. One state, one screen per state. */
sealed class DriveState {
    data object Browsing : DriveState()
    data class Found(val place: Place) : DriveState()
    data object Routing : DriveState()
    data class Choosing(val routes: List<Route>, val place: Place) : DriveState()
    data class Navigating(val place: Place) : DriveState()
}

/** Ferrostar core, location and TTS live for the whole process. */
object Engine {
    private const val TAG = "Engine"
    lateinit var app: Application
    lateinit var alerts: AlertsEngine
    lateinit var places: PlaceStore
    lateinit var prefs: Prefs
    lateinit var account: Account
    lateinit var sources: SourcesStore
    lateinit var push: PushRegistrar
    val markers = MarkerStore()
    /** True between Start and Stop: a reroute that lands after Stop is dropped. */
    @Volatile var tripActive = false

    val location: NavigationLocationProvider by lazy {
        NavigationLocationProvider(
            liveProviding = FusedNavigationLocationProvider(app),
            simulatedProvider = SimulatedLocationProvider(
                warpFactor = 3u,
                initialLocation = UserLocation(
                    GeographicCoordinate(37.3382, -121.8863), 6.0, null, Instant.now(), null,
                ).toAndroidLocation(),
            ),
        )
    }

    val tts: AndroidTtsObserver by lazy { AndroidTtsObserver(app) }

    // One core for the life of the process. The view model subscribes to
    // it once, so it must never be swapped; route options are read at
    // request time by the provider below instead.
    val core: FerrostarCore by lazy { makeCore() }

    /**
     * Routing goes through commutescout.com: the key stays on the server and
     * every route carries the closure exclusions. Units and the avoid
     * options come from Prefs on every request, so a change in Settings
     * applies to the next route without rebuilding the core.
     */
    private class LiveOptionsRouteProvider : CustomRouteProvider {
        override suspend fun getRoutes(userLocation: UserLocation, waypoints: List<Waypoint>): List<Route> {
            val options = mutableMapOf<String, Any>("units" to if (prefs.useMiles) "miles" else "kilometers")
            val costing = prefs.costingOptions
            if (costing.isNotEmpty()) options["costing_options"] = costing
            val adapter = RouteAdapter.fromWellKnownRouteProvider(
                WellKnownRouteProvider.Valhalla(Backend.NAV_ROUTE_URL, "auto").withJsonOptions(options))
            val body = withContext(Dispatchers.IO) {
                val b = Request.Builder()
                when (val req = adapter.generateRequest(userLocation, waypoints)) {
                    is RouteRequest.HttpPost -> {
                        b.url(req.url).post(req.body.toRequestBody("application/json".toMediaType()))
                        req.headers.forEach { (k, v) -> b.header(k, v) }
                    }
                    is RouteRequest.HttpGet -> { b.url(req.url); req.headers.forEach { (k, v) -> b.header(k, v) } }
                }
                Backend.http.newCall(b.build()).execute().use { r ->
                    if (!r.isSuccessful) throw BackendError("Routing answered HTTP ${r.code}.")
                    r.body.bytes()
                }
            }
            return adapter.parseResponse(body)
        }
    }

    private fun makeCore(): FerrostarCore {
        val config = NavigationControllerConfig(
            WaypointAdvanceMode.WaypointWithinRange(100.0),
            stepAdvanceDistanceEntryAndExit(30u, 5u, 32u),
            stepAdvanceDistanceToEndOfStep(10u, 32u),
            RouteDeviationTracking.StaticThreshold(15u, 50.0),
            CourseFiltering.SNAP_TO_ROUTE,
        )
        val core = FerrostarCore(
            routeProvider = RouteProvider.CustomProvider(LiveOptionsRouteProvider()),
            httpClient = Backend.http.toOkHttpClientProvider(),
            locationProvider = location,
            foregroundServiceManager = FerrostarForegroundServiceManager(app, DefaultForegroundNotificationBuilder(app)),
            navigationControllerConfig = config,
            sessionBuilder = FerrostarSessionBuilder(config),
        )
        // Rerouting: when the driver leaves the route, ask for a new one and take it.
        core.deviationHandler = RouteDeviationHandler { _, _, remaining -> CorrectiveAction.GetNewRoutes(remaining) }
        core.alternativeRouteProcessor = AlternativeRouteProcessor { c, routes ->
            // A route fetched for a deviation can land after the driver
            // stopped; replacing the route then would restart the trip.
            Log.i(TAG, "reroute landed: ${routes.size} route(s), tripActive=$tripActive")
            if (!tripActive) return@AlternativeRouteProcessor
            routes.firstOrNull()?.let { r ->
                c.replaceRoute(r)
                // The alerts engine must follow the new geometry.
                alerts.start(r.geometry.map { LatLon(it.lat, it.lng) })
            }
        }
        core.spokenInstructionObserver = tts
        return core
    }

    /**
     * Where the phone last was, without waiting for a fix. Used only to
     * aim the launch snapshot; it is null before the location
     * permission is granted, and the snapshot then waits for the first
     * real fix instead.
     */
    private fun lastKnownPosition(application: Application): LatLon? = runCatching {
        val manager = application.getSystemService(android.content.Context.LOCATION_SERVICE) as android.location.LocationManager
        manager.getProviders(true)
            .mapNotNull { @Suppress("MissingPermission") manager.getLastKnownLocation(it) }
            .maxByOrNull { it.time }
            ?.let { LatLon(it.latitude, it.longitude) }
    }.getOrNull()

    fun init(application: Application) {
        app = application
        prefs = Prefs(application)
        places = PlaceStore(application)
        alerts = AlertsEngine(application)
        account = Account(application)
        sources = SourcesStore(application)
        alerts.spoken = prefs.spokenAlerts
        alerts.announceAheadMeters = prefs.alertAheadMeters
        alerts.rules = { m -> prefs.rule(prefs.ruleKind(m)) }
        // Account sync: plugin choices and places follow the account.
        sources.tokenProvider = { account.token() }
        places.tokenProvider = { account.token() }
        push = PushRegistrar(app, account)
        PushRegistrar.ensureChannel(app)
        account.beforeSignOut = { push.forget() }
        // The dots start loading here, not from the map's first camera
        // callback. This fetch runs beside map setup and the camera
        // animation rather than after both of them, which is the whole
        // difference between markers landing with the camera and
        // several seconds behind it.
        Snapshot.sync(Snapshot.wantedFor(prefs))
        Snapshot.prime(lastKnownPosition(application))
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            account.user.collect { u ->
                if (u != null) { sources.pullFromAccount(); places.syncWithAccount(); push.register() }
            }
        }
        Log.i(TAG, "engine ready")
    }
}

class DriveViewModel : DefaultNavigationViewModel(Engine.core, valhallaExtendedOSRMAnnotationPublisher()) {
    private val _state = MutableStateFlow<DriveState>(DriveState.Browsing)
    val state = _state.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()
    private val _here = MutableStateFlow<LatLon?>(null)
    val here = _here.asStateFlow()
    private val _hasPermission = MutableStateFlow(false)
    val hasPermission = _hasPermission.asStateFlow()
    val simulating = MutableStateFlow(false)
    private val _selectedMarker = MutableStateFlow<RoadMarker?>(null)
    val selectedMarker = _selectedMarker.asStateFlow()
    var isDark by mutableStateOf(false)
    val places get() = Engine.places
    val alerts get() = Engine.alerts
    val prefs get() = Engine.prefs
    val markers get() = Engine.markers
    val account get() = Engine.account
    val sources get() = Engine.sources
    var origin: Place? = null                 // a chosen start instead of the driver

    fun marker(key: String): RoadMarker? = Engine.markers.marker(key) ?: Engine.sources.directMarkers.value.firstOrNull { it.key == key }
    private val _toast = MutableStateFlow<String?>(null)
    val toast = _toast.asStateFlow()

    fun toast(text: String) {
        _toast.value = text
        viewModelScope.launch { kotlinx.coroutines.delay(2500); if (_toast.value == text) _toast.value = null }
    }

    /** Where the driver is pointed, when known. */
    val courseDegrees: Double?
        get() = navigationUiState.value.location?.courseOverGround?.degrees?.toDouble()

    /** Where a report goes: the pin while browsing one, else the driver. */
    /** Where the map is looking, kept by the screen; the report fallback before a fix. */
    var viewCenter: LatLon? = null

    val reportLatLon: LatLon?
        get() = (_state.value as? DriveState.Found)?.place?.let { LatLon(it.lat, it.lon) } ?: _here.value ?: viewCenter

    /** The base map for the current choice and appearance. */
    val styleUrl: String get() = Backend.styleUrl(prefs.mapStyle.serverStyle(isDark))

    // While browsing the puck follows the phone's own fix; Ferrostar only
    // reports a location during a trip.
    private val browsingLocation = MutableStateFlow<UserLocation?>(null)
    override val navigationUiState: StateFlow<NavigationUiState> =
        combine(super.navigationUiState, browsingLocation) { ui, loc ->
            if (ui.isNavigating() || loc == null) ui else ui.copy(location = loc)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), NavigationUiState.empty())

    init {
        viewModelScope.launch {
            navigationUiState.collect { s ->
                s.location?.let { loc ->
                    val p = LatLon(loc.coordinates.lat, loc.coordinates.lng)
                    _here.value = p
                    // On a first run there was no last known position to
                    // aim the snapshot at, and on a long drive the
                    // driver leaves the area it holds.
                    Snapshot.prime(p)
                    if (s.isNavigating()) Engine.alerts.update(p)
                }
            }
        }
    }

    fun setLocationPermission(granted: Boolean) {
        _hasPermission.value = granted
        if (granted) viewModelScope.launch {
            Engine.location.locationUpdates(3000L).collect { l -> browsingLocation.value = l.toUserLocation() }
        }
    }

    fun clearError() { _error.value = null }

    fun applyPrefs() {
        Engine.alerts.spoken = prefs.spokenAlerts
        Engine.alerts.announceAheadMeters = prefs.alertAheadMeters
    }

    fun toggle3D() { prefs.is3D = !prefs.is3D }

    /**
     * A layer was switched. The viewport is asked again for the kinds
     * it serves, and the snapshot behind the roadside layers is loaded
     * or released to match.
     */
    fun layersChanged() {
        Engine.markers.refresh(true)
        Snapshot.sync(Snapshot.wantedFor(prefs))
        Snapshot.prime(_here.value ?: viewCenter)
    }

    // browsing

    fun show(place: Place) {
        _selectedMarker.value = null
        _state.value = DriveState.Found(place)
    }

    fun clearFound() { if (_state.value is DriveState.Found) _state.value = DriveState.Browsing }

    fun showMarker(key: String) {
        val m = marker(key) ?: return
        _selectedMarker.value = m
        if (_state.value is DriveState.Found) _state.value = DriveState.Browsing
    }

    fun clearMarker() { _selectedMarker.value = null }

    /** A long press on the map: a pin named by the platform geocoder. */
    fun dropPin(lat: Double, lon: Double) {
        val pending = Place(name = "%.5f, %.5f".format(lat, lon), lat = lat, lon = lon, kind = PlaceKind.recent)
        show(pending)
        viewModelScope.launch {
            val name = withContext(Dispatchers.IO) {
                runCatching {
                    @Suppress("DEPRECATION")
                    Geocoder(Engine.app, Locale.getDefault()).getFromLocation(lat, lon, 1)?.firstOrNull()?.let { a ->
                        listOfNotNull(a.thoroughfare?.let { t -> a.subThoroughfare?.let { "$it $t" } ?: t } ?: a.featureName, a.locality, a.adminArea)
                            .filter { it.isNotBlank() }.distinct().joinToString(", ")
                    }
                }.getOrNull()
            }
            val cur = _state.value
            if (!name.isNullOrBlank() && cur is DriveState.Found && cur.place.id == pending.id) {
                _state.value = DriveState.Found(pending.copy(name = name))
            }
        }
    }

    // routes

    fun routes(place: Place) {
        val from = origin?.let { LatLon(it.lat, it.lon) } ?: if (simulating.value) LatLon(37.3382, -121.8863) else _here.value
        if (from == null) { _error.value = "Waiting for your location."; return }
        _state.value = DriveState.Routing
        _selectedMarker.value = null
        viewModelScope.launch {
            try {
                val found = withContext(Dispatchers.IO) {
                    Engine.core.getRoutes(
                        UserLocation(GeographicCoordinate(from.lat, from.lon), 6.0, null, Instant.now(), null),
                        listOf(Waypoint(GeographicCoordinate(place.lat, place.lon), WaypointKind.BREAK)),
                    )
                }
                if (found.isEmpty()) throw BackendError("No route found. Try a different destination.")
                _state.value = DriveState.Choosing(found, place)
            } catch (e: Exception) {
                _error.value = e.message?.takeIf { it.isNotBlank() } ?: "Could not get a route. Check your connection and try again."
                _state.value = DriveState.Found(place)
            }
        }
    }

    fun start(route: Route, place: Place) {
        Log.i("DriveViewModel", "start navigation to ${place.shortName}")
        try {
            if (simulating.value) Engine.location.enableSimulationOn(route)
            Engine.tripActive = true
            Engine.core.startNavigation(route)
            setDestination(place.shortName)
            Engine.places.noteRecent(place.name, place.lat, place.lon)
            Engine.alerts.start(route.geometry.map { LatLon(it.lat, it.lng) })
            _selectedMarker.value = null
            _state.value = DriveState.Navigating(place)
        } catch (e: Exception) {
            Log.e("DriveViewModel", "start failed", e)
            _error.value = e.message ?: "Could not start navigation."
        }
    }

    override fun stopNavigation() {
        // The core stops first: switching the location provider while the
        // trip runs looks like a deviation and starts a reroute.
        Engine.tripActive = false
        Engine.core.stopNavigation()
        Engine.location.disableSimulation()
        // A location update already in flight can write a Navigating state
        // after the stop; the core is stopped again if that happens.
        viewModelScope.launch {
            repeat(4) {
                kotlinx.coroutines.delay(750)
                if (!Engine.tripActive && Engine.core.state.value.tripState is uniffi.ferrostar.TripState.Navigating) {
                    Log.w("DriveViewModel", "stop: trip state came back after the stop; stopping again")
                    Engine.core.stopNavigation()
                }
            }
        }
        Engine.alerts.stop()
        _state.value = DriveState.Browsing
    }

    override fun toggleMute() {
        super.toggleMute()
    }
}
