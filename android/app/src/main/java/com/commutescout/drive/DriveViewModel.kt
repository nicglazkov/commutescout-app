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
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock
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
    /** Where the running trip goes, so a reroute can be saved with it. */
    @Volatile var tripPlace: Place? = null
    /** The app is on screen. Off screen with no trip, the pollers rest and location slows down. */
    val foreground = MutableStateFlow(true)
    /** Polling is worth doing: the app is in front, or a trip is running and the service keeps it alive. */
    fun awake() = foreground.value || tripActive
    /** A line for the screen to show as a toast, from work that ran with no screen attached. */
    val notice = MutableStateFlow<String?>(null)
    private val flushLock = kotlinx.coroutines.sync.Mutex()

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
                    if (!r.isSuccessful) throw BackendError("Routing answered HTTP ${r.code}.", r.code)
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
                tripPlace?.let { TripStore.save(r, it) }
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
        androidx.lifecycle.ProcessLifecycleOwner.get().lifecycle.addObserver(object : androidx.lifecycle.DefaultLifecycleObserver {
            override fun onStart(owner: androidx.lifecycle.LifecycleOwner) { foreground.value = true }
            override fun onStop(owner: androidx.lifecycle.LifecycleOwner) { foreground.value = false }
        })
        Connectivity.start(application)
        MapFiles.init(application)
        prefs = Prefs(application)
        places = PlaceStore(application)
        alerts = AlertsEngine(application)
        account = Account(application)
        sources = SourcesStore(application)
        alerts.spoken = prefs.spokenAlerts
        alerts.announceAheadMeters = prefs.alertAheadMeters
        alerts.rules = { m -> prefs.rule(prefs.ruleKind(m)) }
        alerts.fallback = { markers.held() to markers.asOf.value }
        // The signal is back: the snapshot, spoken alerts and any report
        // made meanwhile all catch up. The marker store does its own.
        Connectivity.onReconnect {
            Snapshot.reconnected()
            alerts.refreshNow()
            kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch { flushReports()?.let { notice.value = it } }
        }
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
        val from = lastKnownPosition(application) ?: prefs.lastCenter
        Log.i(TAG, if (from == null) "no position yet; the snapshot waits for the first fix" else "snapshot aimed at $from")
        Snapshot.prime(from)
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main).launch {
            account.user.collect { u ->
                if (u != null) { sources.pullFromAccount(); places.syncWithAccount(); push.register() }
            }
        }
        Log.i(TAG, "engine ready")
    }

    /**
     * Reports made without a signal, sent now. One that waited past
     * [PendingReport.MAX_AGE_MS] is dropped instead, because the server
     * would stamp it as new. Returns what to tell the driver, if anything.
     */
    suspend fun flushReports(): String? = flushLock.withLock {
        val pending = PendingReport.all()
        if (pending.isEmpty() || !Connectivity.online.value) return@withLock null
        val token = account.token() ?: return@withLock null
        val done = PendingReport.flush(pending, System.currentTimeMillis()) { r ->
            Reporter.send(r.kind, r.lat, r.lon, r.heading, r.note, token)
        }
        if (done.dropped + done.refused > 0) Log.i(TAG, "queued reports: ${done.dropped} too old, ${done.refused} refused")
        PendingReport.store(done.waiting)
        if (done.sent.isNotEmpty()) markers.refresh(true)
        done.message()
    }
}

@kotlinx.serialization.Serializable
private data class SpeedLimitAnswer(val kmh: Double? = null, val mph: Double? = null)

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
    /** A trip that was running when the app last closed, offered back. */
    private val _resumable = MutableStateFlow(TripStore.load())
    val resumable = _resumable.asStateFlow()
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
    /** A camera the screen moves to once the map is up (debug hook "csView"). */
    var wantedView: List<Double>? = null
    var wantedTour = false

    val reportLatLon: LatLon?
        get() = (_state.value as? DriveState.Found)?.place?.let { LatLon(it.lat, it.lon) } ?: _here.value ?: viewCenter

    /** The base map for the current choice and appearance: a bundled
     *  style, drawing from the online file or a saved one (MapFiles). */
    val styleJson: String get() = MapFiles.styleJson(prefs.mapStyle.flavor(isDark))

    /** The map along this route, saved for the drive. */
    fun saveTripMap(route: Route, place: Place, manual: Boolean) {
        viewModelScope.launch {
            MapFiles.saveCorridor(route.geometry.map { LatLon(it.lat, it.lng) }, place.shortName, manual, prefs.mapAutoSave)
            MapFiles.notice.value?.let { toast(it); MapFiles.notice.value = null }
        }
    }

    // While browsing the puck follows the phone's own fix; Ferrostar only
    // reports a location during a trip.
    private val browsingLocation = MutableStateFlow<UserLocation?>(null)
    /**
     * Driving mode: the phone is moving at road speed with no trip
     * running. The map turns to face the way the car is pointed and the
     * dot becomes an arrow, as it does on a trip.
     */
    private val _driving = MutableStateFlow(false)
    val driving = _driving.asStateFlow()
    /** The car's course and speed from the last fix, for the arrow. */
    private val _course = MutableStateFlow<Double?>(null)
    val course = _course.asStateFlow()
    private var movingSince = 0L
    private var stillSince = 0L
    /** The last fix's speed in m/s (negative when unknown), for the speedometer. */
    private val _speedMps = MutableStateFlow(-1.0)
    val speedMps = _speedMps.asStateFlow()
    /** The posted limit on the road ahead with no trip, km/h, asked once a minute at most. */
    private val _postedLimitKmh = MutableStateFlow<Double?>(null)
    val postedLimitKmh = _postedLimitKmh.asStateFlow()
    private var limitAskedAt = 0L
    private var limitAskedAtPoint: LatLon? = null
    private var lastFixForSpeed: Pair<LatLon, Long>? = null
    override val navigationUiState: StateFlow<NavigationUiState> =
        combine(super.navigationUiState, browsingLocation) { ui, loc ->
            if (ui.isNavigating() || loc == null) ui else ui.copy(location = loc)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), NavigationUiState.empty())

    init {
        _resumable.value?.let { Log.i("DriveViewModel", "trip to ${it.place.shortName} was running when the app closed; offering it back") }
        viewModelScope.launch { Engine.notice.collect { n -> if (n != null) { toast(n); Engine.notice.value = null } } }
        viewModelScope.launch { MapFiles.notice.collect { n -> if (n != null) { toast(n); MapFiles.notice.value = null } } }
        MapFiles.position = { _here.value ?: viewCenter }
        // The activity was finished under a running trip (a back gesture,
        // a long time away): the service kept the trip, and this new
        // model picks it up instead of stopping its alerts.
        val running = Engine.tripPlace?.takeIf { Engine.tripActive && Engine.core.state.value.tripState is uniffi.ferrostar.TripState.Navigating }
        if (running != null) {
            Log.i("DriveViewModel", "trip to ${running.shortName} still running; picking it up")
            _state.value = DriveState.Navigating(running)
            _resumable.value = null
        } else {
            Engine.alerts.startFreeDrive()
        }
        viewModelScope.launch { Engine.flushReports()?.let { toast(it) } }
        viewModelScope.launch {
            navigationUiState.collect { s ->
                // Arrived: nothing left to resume.
                if (s.tripState is uniffi.ferrostar.TripState.Complete) TripStore.clear()
                s.location?.let { loc ->
                    val p = LatLon(loc.coordinates.lat, loc.coordinates.lng)
                    _here.value = p
                    // The live map asks the server for community plugin
                    // alerts around where this phone actually is, and
                    // gets none at all without saying.
                    LiveData.here = p
                    // On a first run there was no last known position to
                    // aim the snapshot at, and on a long drive the
                    // driver leaves the area it holds.
                    Snapshot.prime(p)
                    if (s.isNavigating()) Engine.alerts.update(p)
                    LiveData.ahead = if (s.isNavigating()) Engine.alerts.stretchAhead() else null
                }
            }
        }
    }

    private var locationJob: Job? = null
    private var locationIntervalMs = 0L

    /**
     * One collector, never two: the activity calls this again after
     * each recreate. Every second on screen or on a trip; off screen
     * with no trip, a fix every fifteen seconds keeps the snapshot aimed
     * without holding the GPS.
     */
    fun setLocationPermission(granted: Boolean) {
        _hasPermission.value = granted
        if (!granted) { locationJob?.cancel(); locationJob = null; return }
        if (locationJob == null) viewModelScope.launch {
            Engine.foreground.collect { collectLocation(if (it || Engine.tripActive) 1000L else 15_000L) }
        }
        collectLocation(if (Engine.awake()) 1000L else 15_000L)
    }

    private fun collectLocation(intervalMs: Long) {
        if (locationJob != null && locationIntervalMs == intervalMs) return
        locationJob?.cancel()
        locationIntervalMs = intervalMs
        locationJob = viewModelScope.launch {
            Engine.location.locationUpdates(intervalMs).collect { l ->
                browsingLocation.value = l.toUserLocation()
                noteFix(l)
            }
        }
    }

    /** A push notification was tapped: the map goes to the spot in its link. */
    fun open(url: String) {
        val u = runCatching { android.net.Uri.parse(url) }.getOrNull() ?: return
        val f = u.getQueryParameter("focus")?.split(",")?.mapNotNull { it.trim().toDoubleOrNull() } ?: return
        if (f.size < 2) return
        Log.i("DriveViewModel", "open from notification: $url")
        wantedView = listOf(f[0], f[1], 13.0)
        val k = u.getQueryParameter("k")
        if (k != null) viewModelScope.launch {
            // The markers may still be loading; the nearest of that kind within 300 m.
            val at = LatLon(f[0], f[1])
            repeat(10) {
                val near = markers.held().filter { it.kind == k && AlertsEngine.meters(LatLon(it.lat, it.lon), at) < 300 }
                    .minByOrNull { AlertsEngine.meters(LatLon(it.lat, it.lon), at) }
                if (near != null) { _selectedMarker.value = near; return@launch }
                kotlinx.coroutines.delay(1000)
            }
        }
    }

    /**
     * Every fix while browsing. Road speed for a few seconds turns
     * driving mode on; a stop of a minute turns it off. A trip has its
     * own camera and its own alerts, so neither changes during one.
     */
    private fun noteFix(l: android.location.Location) {
        val now = System.currentTimeMillis()
        var speed = if (l.hasSpeed()) l.speed.toDouble() else -1.0
        // A fix without a speed: the pace since the last fix stands in.
        val here = LatLon(l.latitude, l.longitude)
        lastFixForSpeed?.let { (p, t) -> if (speed < 0 && now - t > 300) speed = AlertsEngine.meters(p, here) / ((now - t) / 1000.0) }
        lastFixForSpeed = here to now
        val course = if (l.hasBearing() && speed >= 1) l.bearing.toDouble() else null
        if (course != null) _course.value = course
        _speedMps.value = speed
        if (!navigationUiState.value.isNavigating()) {
            Engine.alerts.update(here, course, speed)
            askPostedLimit(here, course, speed)
        }
        if (speed >= 3) {                        // about 7 mph
            stillSince = 0L
            if (movingSince == 0L) movingSince = now
            if (!_driving.value && now - movingSince >= 3000) { _driving.value = true; Log.i("DriveViewModel", "driving mode on") }
        } else if (speed >= 0 && speed < 1) {
            movingSince = 0L
            if (stillSince == 0L) stillSince = now
            if (_driving.value && now - stillSince >= 60_000) { _driving.value = false; Log.i("DriveViewModel", "driving mode off") }
        }
    }

    fun clearError() { _error.value = null }

    fun showError(text: String) { _error.value = text }

    /** Take the saved trip back up; guidance needs only the saved route, not a signal. */
    fun resume() {
        val trip = _resumable.value ?: return
        if (_here.value == null && !simulating.value) { toast("Waiting for your location. Try again in a moment."); return }
        _resumable.value = null
        Log.i("DriveViewModel", "resume trip to ${trip.place.shortName}, saved ${(System.currentTimeMillis() - trip.startedAt) / 1000} s ago")
        start(trip.route, trip.place)
    }

    fun dismissResume() {
        _resumable.value = null
        TripStore.clear()
    }

    /**
     * The limit on the road ahead, once a minute or every 500 m while
     * moving with no trip (a trip's route carries its own). An unknown
     * answer clears the sign rather than leaving a stale one.
     */
    private fun askPostedLimit(p: LatLon, course: Double?, speed: Double) {
        if (speed < 4 || course == null || !Connectivity.online.value) return
        val now = System.currentTimeMillis()
        val moved = limitAskedAtPoint?.let { AlertsEngine.meters(it, p) } ?: Double.MAX_VALUE
        if (now - limitAskedAt < 45_000 && moved < 500) return
        limitAskedAt = now; limitAskedAtPoint = p
        viewModelScope.launch {
            val q = mapOf("lat" to "%.5f".format(p.lat), "lon" to "%.5f".format(p.lon), "heading" to "%.0f".format(course))
            _postedLimitKmh.value = runCatching { Backend.get<SpeedLimitAnswer>("/api/speedlimit", q).kmh }.getOrNull()
        }
    }

    /** The limit to show: the trip's own while navigating, else the posted one. */
    fun limitKmh(ui: NavigationUiState): Double? {
        if (ui.isNavigating()) {
            val sl = runCatching { ui.currentAnnotation?.speedLimit }.getOrNull() ?: return null
            return sl.value(com.stadiamaps.ferrostar.core.measurement.MeasurementSpeedUnit.KilometersPerHour)
        }
        return _postedLimitKmh.value
    }

    /** Whether a marker's plugin takes confirmations (Still there / Gone). */
    fun canConfirm(m: RoadMarker): Boolean {
        if (m.kind != "plugin" || m.id == null) return false
        val sid = PluginStyle.sourceId(m)
        return (sources.catalog.value.firstOrNull { it.id == sid } ?: sources.mine.value.firstOrNull { it.id == sid })?.canConfirm ?: false
    }

    /** A vote on a community report, from the banner: no sheets while driving, a toast says what happened. */
    fun vote(m: RoadMarker, v: String) {
        val id = m.id ?: return
        viewModelScope.launch {
            if (!Connectivity.online.value) { toast("No signal: the vote did not go through."); return@launch }
            val token = account.token() ?: run { toast("Sign in (Settings) to confirm reports."); return@launch }
            runCatching { Reporter.confirm(id, v, token) }
                .onSuccess { toast(if (v == "up") "Thanks, confirmed." else "Thanks, marked as gone.") }
                .onFailure { toast(if (Connectivity.isOffline(it)) "No signal: the vote did not go through." else "Could not record that.") }
        }
    }

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
        if (from == null) {
            // The permission case is the one worth a dialog; a fix on its way is a toast.
            if (!_hasPermission.value) _error.value = "Location is off for CommuteScout Drive. Turn it on in Settings to navigate."
            else toast("Waiting for your location.")
            return
        }
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
                Log.w("DriveViewModel", "routes failed: $e")
                // The raw exception ("Unable to resolve host ...") is for the log, not the driver.
                toast(when {
                    e is BackendError && e.code == 0 && !e.message.isNullOrBlank() -> e.message!!
                    !Connectivity.online.value || Connectivity.isOffline(e) -> OfflineText.ROUTES
                    else -> "Could not get a route. Try again in a moment."
                })
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
            Engine.tripPlace = place
            TripStore.save(route, place)
            saveTripMap(route, place, manual = false)
            setDestination(place.shortName)
            Engine.places.noteRecent(place.name, place.lat, place.lon)
            Engine.alerts.start(route.geometry.map { LatLon(it.lat, it.lng) })
            _selectedMarker.value = null
            _state.value = DriveState.Navigating(place)
        } catch (e: Exception) {
            Log.e("DriveViewModel", "start failed", e)
            toast(if (_here.value == null) "Waiting for your location. Try again in a moment." else "Could not start navigation. Try again.")
        }
    }

    override fun stopNavigation() {
        // The core stops first: switching the location provider while the
        // trip runs looks like a deviation and starts a reroute.
        Engine.tripActive = false
        Engine.tripPlace = null
        TripStore.clear()
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
        Engine.alerts.startFreeDrive()
        _state.value = DriveState.Browsing
    }

    override fun toggleMute() {
        super.toggleMute()
    }
}
