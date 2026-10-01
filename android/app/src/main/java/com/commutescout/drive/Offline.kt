package com.commutescout.drive

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import uniffi.ferrostar.FfiConverterTypeRoute
import uniffi.ferrostar.Route
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Whether the phone can reach the network right now, and what to do the
 * moment it can again.
 *
 * Nothing waits on this before trying: a request is always the real
 * test. It decides what the app says (the offline banner, an honest
 * error) and it is the trigger for catching up once the signal is back:
 * markers, spoken alerts and any reports queued meanwhile.
 */
object Connectivity {
    private const val TAG = "Connectivity"
    private val _online = MutableStateFlow(true)
    val online = _online.asStateFlow()
    /** On Wi-Fi or wired, as opposed to a mobile data plan. */
    private val _onWifi = MutableStateFlow(false)
    val onWifi = _onWifi.asStateFlow()
    private val reconnect = CopyOnWriteArrayList<() -> Unit>()
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private var started = false

    fun start(context: Context) {
        if (started) return
        started = true
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        val caps0 = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
        _online.value = caps0?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        _onWifi.value = caps0?.let(::wifi) == true
        runCatching {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    _onWifi.value = wifi(caps)
                    set(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
                }
                override fun onLost(network: Network) { _onWifi.value = false; set(false) }
                override fun onUnavailable() { _onWifi.value = false; set(false) }
            })
        }.onFailure { Log.w(TAG, "could not watch the network: $it") }
    }

    private fun wifi(caps: NetworkCapabilities) =
        (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)

    /** Run [action] on the main thread every time the network comes back. */
    fun onReconnect(action: () -> Unit) { reconnect.add(action) }

    private fun set(up: Boolean) {
        if (up == _online.value) return
        _online.value = up
        Log.i(TAG, if (up) "network: back" else "network: lost")
        if (up) main.post { reconnect.forEach { runCatching { it() } } }
    }

    /** Errors that mean the network was not there, as opposed to a server that answered and said no. */
    fun isOffline(e: Throwable?): Boolean = when (e) {
        null -> false
        is UnknownHostException, is ConnectException, is NoRouteToHostException, is SocketTimeoutException -> true
        is InterruptedIOException -> e.message?.contains("timeout", ignoreCase = true) == true
        else -> isOffline(e.cause)
    }
}

/** What the app says when something needs the network and there is none. */
object OfflineText {
    const val ROUTES = "No connection. Routes need a signal. Your saved places and the map you already loaded still work."
    const val SEARCH = "No connection. Search needs a signal. Saved and recent places still work."
    const val RETRY = "No connection. Try again when you have a signal."
    const val CAMERA = "No connection, so the picture cannot load."

    /** A short clock time, the way the phone shows it. */
    fun time(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
}

/**
 * How long a road event can be trusted without a fresh copy. A report of
 * police is stale in half an hour; a closure for roadwork lasts all day.
 * Only ever applied to data that could not be refreshed: while the phone
 * is online everything is minutes old anyway.
 */
object ShelfLife {
    /** Past this, nothing saved is shown at all. */
    const val MAX_AGE_MS = 24 * 3600_000L

    fun millis(kind: String): Long = when (kind) {
        "plugin" -> 30 * 60_000L
        "incident", "sign", "toll" -> 60 * 60_000L
        "rwis" -> 2 * 3600_000L
        "chain_control" -> 6 * 3600_000L
        "lane_closure" -> 12 * 3600_000L
        else -> MAX_AGE_MS        // wildfires, cameras
    }

    fun keep(kind: String, ageMs: Long): Boolean = ageMs <= millis(kind)

    /** The markers still worth showing when the newest copy is from [asOf]. */
    fun prune(markers: List<RoadMarker>, asOf: Long?, now: Long = System.currentTimeMillis()): List<RoadMarker> {
        if (asOf == null) return markers
        val age = now - asOf
        if (age <= 15 * 60_000L) return markers   // nothing expires this quickly
        return markers.filter { keep(it.kind, age) }
    }
}

/**
 * Files kept on the phone so the app has something to show without a
 * signal: the last snapshot of road markers (in the cache directory,
 * which the system may clear), and the running trip and unsent reports
 * (in app storage, which it does not).
 */
object OfflineStore {
    fun cache(name: String): File = File(File(Engine.app.cacheDir, "offline").apply { mkdirs() }, name)
    fun kept(name: String): File = File(File(Engine.app.filesDir, "offline").apply { mkdirs() }, name)

    /** Write through a temporary file, so a half-written file never replaces a good one. */
    fun write(file: File, block: (java.io.OutputStream) -> Unit) {
        val part = File(file.path + ".part")
        try {
            part.outputStream().buffered().use(block)
            if (!part.renameTo(file)) { file.delete(); part.renameTo(file) }
        } finally {
            part.delete()
        }
    }
}

/** The trip in progress, as saved when it started. */
data class SavedTrip(val route: Route, val place: Place, val startedAt: Long)

/**
 * The trip in progress, written when it starts and removed when it ends,
 * so an app that was closed or killed mid-drive can pick the route up
 * again without a signal. Guidance only needs the route.
 *
 * The route is written in Ferrostar's own binary form, which is tied to
 * its version: a trip saved by a build with an older Ferrostar may not
 * read back, and is then dropped rather than guessed at.
 */
object TripStore {
    private const val TAG = "TripStore"
    private const val FILE = "trip.bin"
    private const val FORMAT = 1
    /** A trip left this long is not one anybody is still on. */
    private const val MAX_AGE_MS = 12 * 3600_000L

    @Serializable
    private data class Meta(val place: Place, val startedAt: Long)

    fun save(route: Route, place: Place) {
        runCatching {
            val size = FfiConverterTypeRoute.allocationSize(route).toInt()
            val buf = ByteBuffer.allocate(size)
            FfiConverterTypeRoute.write(route, buf)
            val meta = Backend.json.encodeToString(Meta.serializer(), Meta(place, System.currentTimeMillis())).toByteArray()
            OfflineStore.write(OfflineStore.kept(FILE)) { raw ->
                DataOutputStream(raw).apply {
                    writeInt(FORMAT); writeInt(meta.size); write(meta); writeInt(size); write(buf.array(), 0, size); flush()
                }
            }
        }.onFailure { Log.w(TAG, "could not save the trip: $it") }
    }

    fun load(): SavedTrip? {
        val file = OfflineStore.kept(FILE)
        if (!file.exists()) return null
        if (System.currentTimeMillis() - file.lastModified() > MAX_AGE_MS) { clear(); return null }
        return runCatching {
            DataInputStream(file.inputStream().buffered()).use { input ->
                check(input.readInt() == FORMAT)
                val meta = ByteArray(input.readInt()).also { input.readFully(it) }
                val bytes = ByteArray(input.readInt()).also { input.readFully(it) }
                val m = Backend.json.decodeFromString(Meta.serializer(), String(meta))
                SavedTrip(FfiConverterTypeRoute.read(ByteBuffer.wrap(bytes)), m.place, m.startedAt)
            }
        }.getOrElse { Log.w(TAG, "saved trip unreadable, dropped: $it"); clear(); null }
    }

    fun clear() { OfflineStore.kept(FILE).delete() }
}

/**
 * A report made with no signal, sent once it is back.
 *
 * The server stamps a report with the time it arrives, so one that
 * waited too long would land on the map as fresh news about something
 * that may be long gone. A report older than [MAX_AGE_MS] is dropped
 * instead of sent.
 */
@Serializable
data class PendingReport(
    val kind: String,
    val lat: Double,
    val lon: Double,
    val heading: Double? = null,
    val note: String = "",
    val createdAt: Long,
) {
    companion object {
        const val MAX_AGE_MS = 15 * 60_000L
        private const val FILE = "pending-reports.json"
        private val lock = Any()

        fun all(): List<PendingReport> = synchronized(lock) {
            val file = OfflineStore.kept(FILE)
            if (!file.exists()) return emptyList()
            runCatching { Backend.json.decodeFromString(ListSerializer(serializer()), file.readText()) }.getOrDefault(emptyList())
        }

        fun store(list: List<PendingReport>) {
            synchronized(lock) {
                val file = OfflineStore.kept(FILE)
                if (list.isEmpty()) { file.delete(); return }
                OfflineStore.write(file) { it.write(Backend.json.encodeToString(ListSerializer(serializer()), list).toByteArray()) }
            }
        }

        fun add(report: PendingReport) { synchronized(lock) { store(all() + report) } }
    }
}
