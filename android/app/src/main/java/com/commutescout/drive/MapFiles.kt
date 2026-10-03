package com.commutescout.drive

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File

/**
 * Our own base map.
 *
 * The map is drawn from a vector tile archive (PMTiles) of the United
 * States on the data host, read by byte range, with three styles and
 * their fonts and sprites bundled in the app so the map draws with no
 * signal at all. For driving through a dead zone the phone keeps pieces
 * of that archive on disk: a corridor cut for the trip when it starts,
 * and whole states the driver chooses in Settings. When the signal goes,
 * the map is pointed at the best local file; when it is back, at the
 * online one again.
 */
object MapFiles {
    private const val TAG = "MapFiles"
    const val DEFAULT_US = "https://data.commutescout.com/map/us.pmtiles"
    val flavors = listOf("light", "dark", "grayscale")
    /** A trip corridor is kept this long; it is for one drive. */
    private const val CORRIDOR_KEEP_MS = 7 * 24 * 3600_000L
    private const val CORRIDOR_MAX = 6

    @Serializable data class Entry(val url: String, val bytes: Long? = null)
    @Serializable data class StateFile(val code: String, val name: String, val bytes: Long? = null, val url: String)
    @Serializable data class Corridor(val buffer_m: Double = 2500.0, val max_route_m: Double = 800_000.0)
    @Serializable data class Manifest(val build: String? = null, val us: Entry, val assets: String = "",
                                      val states: List<StateFile> = emptyList(), val corridor: Corridor = Corridor())

    /** A map file on the phone and the ground it covers. */
    @Serializable
    data class LocalFile(
        val id: String, val kind: String, val name: String, val bytes: Long,
        val south: Double, val west: Double, val north: Double, val east: Double,
        val savedAt: Long, val build: String? = null,
        /** A corridor's route, thinned, so the detail sheet can draw the ground the file really covers. */
        val path: List<List<Double>>? = null,
    ) {
        fun covers(p: LatLon) = p.lat in south..north && p.lon in west..east
        val sizeText: String get() = Units.bytes(bytes)
    }

    private lateinit var app: Context
    private lateinit var folder: File
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _manifest = MutableStateFlow<Manifest?>(null)
    val manifest = _manifest.asStateFlow()
    private val _files = MutableStateFlow<List<LocalFile>>(emptyList())
    val files = _files.asStateFlow()
    /** Downloads in flight, by file id, 0 to 1. */
    private val _progress = MutableStateFlow<Map<String, Float>>(emptyMap())
    val progress = _progress.asStateFlow()
    /** The local file the map is drawing from, or null while online. */
    private val _usingLocal = MutableStateFlow<LocalFile?>(null)
    val usingLocal = _usingLocal.asStateFlow()
    /** A line for the screen to show as a toast. */
    val notice = MutableStateFlow<String?>(null)
    /** Where the phone is, for choosing which local file to draw from. */
    var position: (() -> LatLon?)? = null

    fun init(context: Context) {
        app = context.applicationContext
        folder = File(app.filesDir, "maps").apply { mkdirs() }
        _files.value = runCatching {
            Backend.json.decodeFromString(ListSerializer(LocalFile.serializer()), File(folder, "files.json").readText())
        }.getOrDefault(emptyList()).filter { path(it).exists() }
        _manifest.value = runCatching { Backend.json.decodeFromString(Manifest.serializer(), File(folder, "manifest.json").readText()) }.getOrNull()
        scope.launch { Connectivity.online.collect { up -> networkChanged(up) } }
        scope.launch { refreshManifest() }
        pruneCorridors()
    }

    // ---------------------------------------------------------------- style

    /**
     * The style the map loads: the bundled style for [flavor] with the
     * fonts and sprites pointed into the app's assets and the tiles
     * pointed at the online file, or at the local one while offline.
     */
    fun styleJson(flavor: String): String {
        val text = app.assets.open("map/styles/$flavor.json").bufferedReader().use { it.readText() }
        return text.replace("__PMTILES_URL__", tileSource()).replace("__ASSETS__", "asset://map")
    }

    /** Changes whenever the style the map should load changes. */
    val styleKey: String get() = tileSource()

    private fun tileSource(): String {
        _usingLocal.value?.let { return "file://" + path(it).absolutePath }
        return _manifest.value?.us?.url ?: DEFAULT_US
    }

    // --------------------------------------------------------- online, offline

    private fun networkChanged(up: Boolean) {
        if (up) {
            if (_usingLocal.value != null) { _usingLocal.value = null; Log.i(TAG, "back online, drawing from the online file") }
            return
        }
        // A moment's grace: a signal that flickers should not reload the map twice.
        scope.launch { delay(4000); if (!Connectivity.online.value) pickLocal() }
    }

    /**
     * With no signal, draw from the local file that covers the phone: a
     * state first (it covers more), else the newest corridor, else any
     * file at all rather than nothing.
     */
    fun pickLocal() {
        val all = _files.value
        if (all.isEmpty()) return
        val here = position?.invoke()
        val covering = all.filter { here != null && it.covers(here) }
        val choice = covering.firstOrNull { it.kind == "state" } ?: covering.maxByOrNull { it.savedAt } ?: all.maxByOrNull { it.savedAt }
        if (choice != _usingLocal.value) {
            _usingLocal.value = choice
            Log.i(TAG, "offline, drawing from ${choice?.name} (${choice?.kind})")
        }
    }

    // ------------------------------------------------------------- manifest

    suspend fun refreshManifest() {
        if (!Connectivity.online.value) return
        runCatching { Backend.get<Manifest>("/api/map/manifest", emptyMap()) }
            .onSuccess { m -> _manifest.value = m; runCatching { File(folder, "manifest.json").writeText(Backend.json.encodeToString(Manifest.serializer(), m)) } }
            .onFailure { Log.w(TAG, "manifest unavailable: $it") }
    }

    // ------------------------------------------------------------ downloads

    /**
     * The corridor for a trip. Automatic only on Wi-Fi with the setting
     * on; [manual] is the driver's own tap, on any network.
     */
    suspend fun saveCorridor(route: List<LatLon>, name: String, manual: Boolean, autoAllowed: Boolean): LocalFile? {
        if (!Connectivity.online.value || route.size < 2) return null
        if (!manual && !(autoAllowed && Connectivity.onWifi.value)) {
            Log.i(TAG, "corridor not saved automatically (wifi=${Connectivity.onWifi.value}, setting=$autoAllowed)"); return null
        }
        val id = "corridor-" + System.currentTimeMillis() / 1000
        if (_progress.value.containsKey(id)) return null
        setProgress(id, 0f)
        try {
            val pad = (_manifest.value?.corridor?.buffer_m ?: 2500.0) / 100_000
            val step = maxOf(1, route.size / 2000 + 1)
            val body = buildJsonObject {
                put("path", buildJsonArray { for (i in route.indices step step) add(JsonArray(listOf(JsonPrimitive(route[i].lat), JsonPrimitive(route[i].lon)))) })
            }.toString()
            val file = LocalFile(id, "corridor", "Trip to $name", 0,
                route.minOf { it.lat } - pad, route.minOf { it.lon } - pad, route.maxOf { it.lat } + pad, route.maxOf { it.lon } + pad,
                System.currentTimeMillis(), _manifest.value?.build)
            val written = withContext(Dispatchers.IO) {
                val req = Request.Builder().url("${Backend.BASE}/api/map/extract").post(body.toRequestBody("application/json".toMediaType())).build()
                Backend.http.newBuilder().callTimeout(0, java.util.concurrent.TimeUnit.SECONDS).readTimeout(300, java.util.concurrent.TimeUnit.SECONDS).build()
                    .newCall(req).execute().use { r ->
                        if (!r.isSuccessful) throw BackendError("HTTP ${r.code}", r.code)
                        write(r.body.byteStream(), r.body.contentLength(), path(file), id)
                    }
            }
            val thin = maxOf(1, route.size / 300 + 1)
            val done = file.copy(bytes = written, path = (route.indices step thin).map { listOf(route[it].lat, route[it].lon) })
            _files.value = _files.value + done
            persist(); pruneCorridors()
            Log.i(TAG, "corridor saved, ${done.sizeText}")
            notice.value = "Map for this trip saved (${done.sizeText})."
            return done
        } catch (e: Exception) {
            Log.w(TAG, "corridor failed: $e")
            if (manual) notice.value = if (Connectivity.isOffline(e)) OfflineText.RETRY else "Could not save the map for this trip."
            return null
        } finally { clearProgress(id) }
    }

    suspend fun downloadState(s: StateFile) {
        val id = "state-${s.code}"
        if (_progress.value.containsKey(id) || !Connectivity.online.value) return
        setProgress(id, 0f)
        val b = StateBounds.of(s.code)
        val file = LocalFile(id, "state", s.name, s.bytes ?: 0, b[0], b[1], b[2], b[3], System.currentTimeMillis(), _manifest.value?.build)
        try {
            val written = withContext(Dispatchers.IO) {
                val req = Request.Builder().url(s.url).build()
                Backend.http.newBuilder().callTimeout(0, java.util.concurrent.TimeUnit.SECONDS).readTimeout(600, java.util.concurrent.TimeUnit.SECONDS).build()
                    .newCall(req).execute().use { r ->
                        if (!r.isSuccessful) throw BackendError("HTTP ${r.code}", r.code)
                        write(r.body.byteStream(), r.body.contentLength(), path(file), id)
                    }
            }
            val done = file.copy(bytes = written)
            _files.value = _files.value.filter { it.id != id } + done
            persist()
            notice.value = "${s.name} saved (${done.sizeText})."
            Log.i(TAG, "state ${s.code} saved, ${done.sizeText}")
        } catch (e: Exception) {
            path(file).delete()
            notice.value = if (Connectivity.isOffline(e)) OfflineText.RETRY else "Could not download ${s.name}."
            Log.w(TAG, "state ${s.code} failed: $e")
        } finally { clearProgress(id) }
    }

    fun delete(f: LocalFile) {
        path(f).delete()
        _files.value = _files.value.filter { it.id != f.id }
        if (_usingLocal.value?.id == f.id) { _usingLocal.value = null; pickLocal() }
        persist()
    }

    val bytesOnDisk: Long get() = _files.value.sumOf { it.bytes }
    fun has(state: String): LocalFile? = _files.value.firstOrNull { it.id == "state-$state" }

    // ---------------------------------------------------------------- files

    fun path(f: LocalFile) = File(folder, "${f.id}.pmtiles")

    /**
     * The outline of a state, from the site's us-states.json (the file
     * the map build cuts the state files with), cached on the phone.
     * Each ring is a list of lon,lat positions.
     */
    suspend fun stateOutline(name: String): List<List<Pair<Double, Double>>>? = withContext(Dispatchers.IO) {
        val local = File(app.cacheDir, "us-states.json")
        val text = runCatching { if (local.exists()) local.readText() else null }.getOrNull() ?: runCatching {
            Backend.http.newCall(Request.Builder().url("https://commutescout.com/static/us-states.json").build()).execute().use { r ->
                if (!r.isSuccessful) null else r.body.string().also { local.writeText(it) }
            }
        }.getOrNull() ?: return@withContext null
        val features = runCatching { Backend.json.parseToJsonElement(text).jsonObject["features"]!!.jsonArray }.getOrNull() ?: return@withContext null
        for (f in features) {
            val obj = f.jsonObject
            if (obj["properties"]?.jsonObject?.get("NAME")?.jsonPrimitive?.content != name) continue
            val geom = obj["geometry"]?.jsonObject ?: continue
            val type = geom["type"]?.jsonPrimitive?.content
            val coords = geom["coordinates"]?.jsonArray ?: continue
            fun ring(r: JsonElement) = r.jsonArray.map { p -> p.jsonArray[0].jsonPrimitive.double to p.jsonArray[1].jsonPrimitive.double }
            return@withContext when (type) {
                "Polygon" -> listOf(ring(coords[0]))
                "MultiPolygon" -> coords.map { ring(it.jsonArray[0]) }
                else -> null
            }
        }
        null
    }

    /** What the disk says about a saved map, for the detail sheet: a double check on the record the app kept. */
    suspend fun check(f: LocalFile): MapFileCheck = withContext(Dispatchers.IO) {
        val file = path(f)
        if (!file.exists()) MapFileCheck(false, 0, null) else MapFileCheck(true, file.length(), PMTilesHeader.read(file))
    }

    private fun persist() {
        runCatching { File(folder, "files.json").writeText(Backend.json.encodeToString(ListSerializer(LocalFile.serializer()), _files.value)) }
    }

    private fun pruneCorridors() {
        val corridors = _files.value.filter { it.kind == "corridor" }.sortedByDescending { it.savedAt }
        corridors.forEachIndexed { i, c -> if (i >= CORRIDOR_MAX || System.currentTimeMillis() - c.savedAt > CORRIDOR_KEEP_MS) delete(c) }
    }

    private fun setProgress(id: String, p: Float) { _progress.value = _progress.value + (id to p) }
    private fun clearProgress(id: String) { _progress.value = _progress.value - id }

    /** Stream a response to disk, reporting progress; returns the byte count. */
    private fun write(input: java.io.InputStream, total: Long, target: File, id: String): Long {
        val part = File(target.path + ".part")
        var count = 0L
        part.outputStream().buffered(1 shl 20).use { out ->
            val buf = ByteArray(1 shl 16)
            var last = 0L
            while (true) {
                val n = input.read(buf); if (n < 0) break
                out.write(buf, 0, n); count += n
                if (total > 0 && count - last > (1 shl 20)) { last = count; scope.launch { setProgress(id, (count.toDouble() / total).toFloat()) } }
            }
        }
        target.delete()
        if (!part.renameTo(target)) throw BackendError("could not move the map file into place")
        return count
    }
}

/**
 * Rough bounds per state (south, west, north, east), for choosing which
 * saved state covers the phone. Generous on purpose.
 */
object StateBounds {
    private val T = mapOf(
        "AL" to doubleArrayOf(30.1, -88.6, 35.1, -84.8), "AK" to doubleArrayOf(51.0, -180.0, 72.0, -129.0), "AZ" to doubleArrayOf(31.2, -115.0, 37.1, -108.9),
        "AR" to doubleArrayOf(32.9, -94.7, 36.6, -89.5), "CA" to doubleArrayOf(32.4, -124.6, 42.1, -114.0), "CO" to doubleArrayOf(36.9, -109.2, 41.1, -101.9),
        "CT" to doubleArrayOf(40.9, -73.8, 42.1, -71.7), "DE" to doubleArrayOf(38.4, -75.9, 39.9, -74.9), "FL" to doubleArrayOf(24.3, -87.7, 31.1, -79.9),
        "GA" to doubleArrayOf(30.3, -85.7, 35.1, -80.7), "HI" to doubleArrayOf(18.8, -160.4, 22.4, -154.7), "ID" to doubleArrayOf(41.9, -117.3, 49.1, -110.9),
        "IL" to doubleArrayOf(36.9, -91.6, 42.6, -87.4), "IN" to doubleArrayOf(37.7, -88.2, 41.8, -84.7), "IA" to doubleArrayOf(40.3, -96.7, 43.6, -90.0),
        "KS" to doubleArrayOf(36.9, -102.1, 40.1, -94.5), "KY" to doubleArrayOf(36.4, -89.6, 39.2, -81.9), "LA" to doubleArrayOf(28.8, -94.1, 33.1, -88.7),
        "ME" to doubleArrayOf(42.9, -71.2, 47.5, -66.8), "MD" to doubleArrayOf(37.8, -79.6, 39.8, -74.9), "MA" to doubleArrayOf(41.1, -73.6, 42.9, -69.8),
        "MI" to doubleArrayOf(41.6, -90.5, 48.4, -82.3), "MN" to doubleArrayOf(43.4, -97.3, 49.5, -89.4), "MS" to doubleArrayOf(30.0, -91.7, 35.1, -88.0),
        "MO" to doubleArrayOf(35.9, -95.8, 40.7, -89.0), "MT" to doubleArrayOf(44.3, -116.1, 49.1, -104.0), "NE" to doubleArrayOf(39.9, -104.1, 43.1, -95.2),
        "NV" to doubleArrayOf(34.9, -120.1, 42.1, -113.9), "NH" to doubleArrayOf(42.6, -72.6, 45.4, -70.6), "NJ" to doubleArrayOf(38.8, -75.6, 41.4, -73.8),
        "NM" to doubleArrayOf(31.2, -109.1, 37.1, -102.9), "NY" to doubleArrayOf(40.4, -79.8, 45.1, -71.8), "NC" to doubleArrayOf(33.7, -84.4, 36.7, -75.4),
        "ND" to doubleArrayOf(45.9, -104.1, 49.1, -96.5), "OH" to doubleArrayOf(38.3, -84.9, 42.0, -80.4), "OK" to doubleArrayOf(33.5, -103.1, 37.1, -94.3),
        "OR" to doubleArrayOf(41.9, -124.7, 46.4, -116.4), "PA" to doubleArrayOf(39.6, -80.6, 42.4, -74.6), "RI" to doubleArrayOf(41.1, -71.9, 42.1, -71.0),
        "SC" to doubleArrayOf(31.9, -83.4, 35.3, -78.4), "SD" to doubleArrayOf(42.4, -104.1, 46.0, -96.3), "TN" to doubleArrayOf(34.9, -90.4, 36.8, -81.6),
        "TX" to doubleArrayOf(25.7, -106.7, 36.6, -93.4), "UT" to doubleArrayOf(36.9, -114.1, 42.1, -108.9), "VT" to doubleArrayOf(42.6, -73.5, 45.1, -71.4),
        "VA" to doubleArrayOf(36.4, -83.7, 39.6, -75.1), "WA" to doubleArrayOf(45.4, -124.9, 49.1, -116.8), "WV" to doubleArrayOf(37.1, -82.7, 40.7, -77.6),
        "WI" to doubleArrayOf(42.4, -92.9, 47.2, -86.7), "WY" to doubleArrayOf(40.9, -111.1, 45.1, -104.0), "DC" to doubleArrayOf(38.7, -77.2, 39.1, -76.8),
    )
    fun of(code: String): DoubleArray = T[code] ?: doubleArrayOf(24.0, -125.0, 50.0, -66.0)
}
