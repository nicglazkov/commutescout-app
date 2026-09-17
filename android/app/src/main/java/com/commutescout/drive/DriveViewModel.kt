package com.commutescout.drive

import android.app.Application
import android.util.Log
import androidx.lifecycle.viewModelScope
import com.stadiamaps.ferrostar.composeui.notification.DefaultForegroundNotificationBuilder
import com.stadiamaps.ferrostar.core.AlternativeRouteProcessor
import com.stadiamaps.ferrostar.core.AndroidTtsObserver
import com.stadiamaps.ferrostar.core.CorrectiveAction
import com.stadiamaps.ferrostar.core.DefaultNavigationViewModel
import com.stadiamaps.ferrostar.core.FerrostarCore
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
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
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

    val core: FerrostarCore by lazy {
        // Routing goes through commutescout.com: the key stays on the
        // server and every route carries the closure exclusions.
        val provider = WellKnownRouteProvider.Valhalla(Backend.NAV_ROUTE_URL, "auto")
            .withJsonOptions(mapOf("units" to if (Units.useMiles) "miles" else "kilometers"))
        val core = FerrostarCore(
            wellKnownRouteProvider = provider,
            httpClient = Backend.http.toOkHttpClientProvider(),
            locationProvider = location,
            foregroundServiceManager = FerrostarForegroundServiceManager(app, DefaultForegroundNotificationBuilder(app)),
            navigationControllerConfig = NavigationControllerConfig(
                WaypointAdvanceMode.WaypointWithinRange(100.0),
                stepAdvanceDistanceEntryAndExit(30u, 5u, 32u),
                stepAdvanceDistanceToEndOfStep(10u, 32u),
                RouteDeviationTracking.StaticThreshold(15u, 50.0),
                CourseFiltering.SNAP_TO_ROUTE,
            ),
        )
        // Rerouting: when the driver leaves the route, ask for a new one and take it.
        core.deviationHandler = RouteDeviationHandler { _, _, remaining -> CorrectiveAction.GetNewRoutes(remaining) }
        core.alternativeRouteProcessor = AlternativeRouteProcessor { c, routes ->
            if (routes.isNotEmpty()) c.replaceRoute(routes.first())
        }
        core.spokenInstructionObserver = tts
        core
    }

    fun init(application: Application) {
        app = application
        Units.init(application)
        places = PlaceStore(application)
        alerts = AlertsEngine(application)
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
    val places get() = Engine.places
    val alerts get() = Engine.alerts

    init {
        viewModelScope.launch {
            navigationUiState.collect { s ->
                s.location?.let { loc ->
                    val p = LatLon(loc.coordinates.lat, loc.coordinates.lng)
                    _here.value = p
                    if (s.isNavigating()) Engine.alerts.update(p)
                }
            }
        }
    }

    fun setLocationPermission(granted: Boolean) {
        _hasPermission.value = granted
        if (granted) viewModelScope.launch {
            Engine.location.locationUpdates(5000L).collect { l ->
                if (!navigationUiState.value.isNavigating()) _here.value = LatLon(l.latitude, l.longitude)
            }
        }
    }

    fun clearError() { _error.value = null }

    // browsing

    fun show(place: Place) { _state.value = DriveState.Found(place) }

    fun clearFound() { if (_state.value is DriveState.Found) _state.value = DriveState.Browsing }

    // routes

    fun routes(place: Place) {
        val from = if (simulating.value) LatLon(37.3382, -121.8863) else _here.value
        if (from == null) { _error.value = "Waiting for your location."; return }
        _state.value = DriveState.Routing
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
                _error.value = e.message ?: "Could not get a route."
                _state.value = DriveState.Found(place)
            }
        }
    }

    fun start(route: Route, place: Place) {
        try {
            if (simulating.value) Engine.location.enableSimulationOn(route)
            Engine.core.startNavigation(route)
            setDestination(place.shortName)
            Engine.places.noteRecent(place.name, place.lat, place.lon)
            Engine.alerts.start(route.geometry.map { LatLon(it.lat, it.lng) })
            _state.value = DriveState.Navigating(place)
        } catch (e: Exception) {
            _error.value = e.message ?: "Could not start navigation."
        }
    }

    override fun stopNavigation() {
        Engine.location.disableSimulation()
        Engine.core.stopNavigation()
        Engine.alerts.stop()
        _state.value = DriveState.Browsing
    }

    override fun toggleMute() {
        super.toggleMute()
        Engine.alerts.spoken = Engine.core.spokenInstructionObserver?.isMuted != true
    }
}
