package com.commutescout.drive

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.json.decodeFromStream
import okhttp3.Request

/**
 * The nationwide marker snapshots the website boots from.
 *
 * A publisher writes one pre-gzipped object per bundle to a CDN, so the
 * first paint costs a single edge-cached GET rather than a live query
 * against warming feeds. The app starts that GET at launch, next to map
 * setup and the camera animation, so the dots are already in memory by
 * the time the camera finishes settling on the driver.
 *
 * The snapshots are slim: they carry every dot but no closure stretch
 * or toll corridor geometry. That geometry only ever comes from
 * /api/mapdata, so [MarkerStore] keeps asking for a viewport and the
 * lines fill in behind the dots. The snapshot never replaces it.
 */
object Snapshot {
    private const val TAG = "Snapshot"
    private const val BASE = "https://data.commutescout.com"

    /** How far either side of the driver a snapshot is kept, in degrees. */
    private const val LAT_PAD = 2.5
    private const val LON_PAD = 3.0

    /** A held bundle is re-read at this age, so signs and prices stay live. */
    private const val MAX_AGE_MS = 300_000L

    enum class Bundle(val file: String) {
        /** Incidents, closures, chain controls, wildfires, tolls and community reports. */
        LIVE("live.json.gz"),

        /** Message signs and roadside weather stations, both on by default. */
        SIGNS("signs.json.gz"),

        /** Cameras, the largest bundle, fetched the first time the layer is switched on. */
        CAMERAS("cameras.json.gz"),
    }

    private val _markers = MutableStateFlow<List<RoadMarker>>(emptyList())

    /** Every marker held for the area around the driver, across bundles. */
    val markers = _markers.asStateFlow()

    private val held = HashMap<Bundle, List<RoadMarker>>()
    private val loadedAt = HashMap<Bundle, Long>()
    private val jobs = HashMap<Bundle, Job>()
    private var wanted = setOf(Bundle.LIVE)
    private var box: DoubleArray? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ticker: Job? = null

    /**
     * Point the snapshots at a place and start loading. Called with the
     * last known position at launch, again with the first live fix, and
     * again whenever the driver leaves the middle of the held area.
     */
    fun prime(center: LatLon?) {
        if (center != null && !wellInside(center)) {
            box = doubleArrayOf(center.lat - LAT_PAD, center.lon - LON_PAD, center.lat + LAT_PAD, center.lon + LON_PAD)
            // The held markers were cut to the old area, so every
            // bundle is read again against the new one.
            loadedAt.clear()
        }
        if (box == null) return
        sync(wanted)
        if (ticker == null) ticker = scope.launch {
            while (isActive) { delay(MAX_AGE_MS); sync(wanted) }
        }
    }

    /**
     * Hold exactly the bundles the switched-on layers need. A layer
     * switched off frees its markers; one switched back on loads again.
     */
    fun sync(bundles: Set<Bundle>) {
        wanted = bundles
        for (b in Bundle.entries) {
            if (b !in bundles) {
                jobs.remove(b)?.cancel()
                if (held.remove(b) != null) { loadedAt.remove(b); publish() }
                continue
            }
            val fresh = System.currentTimeMillis() - (loadedAt[b] ?: 0L) < MAX_AGE_MS
            if (fresh || jobs[b]?.isActive == true || box == null) continue
            start(b)
        }
    }

    /**
     * The bundles the switched-on layers need. Live is always held: it
     * is what paints the map before anything else arrives. Signs and
     * weather stations share one bundle and both start switched on, so
     * it loads at launch too. Cameras start off and cost the most, so
     * that one waits to be asked for.
     */
    fun wantedFor(prefs: Prefs): Set<Bundle> = buildSet {
        add(Bundle.LIVE)
        if (prefs.isShown("sign") || prefs.isShown("rwis")) add(Bundle.SIGNS)
        if (prefs.isShown("camera")) add(Bundle.CAMERAS)
    }

    private fun start(b: Bundle) {
        val target = box ?: return
        loadedAt[b] = System.currentTimeMillis()
        jobs[b] = scope.launch {
            val began = System.currentTimeMillis()
            val found = runCatching { load(b, target) }.getOrElse { e ->
                Log.w(TAG, "${b.file} did not load (${e.message})")
                loadedAt.remove(b)
                return@launch
            }
            // The area can move while a bundle is in flight; a reply for
            // an area the driver already left is not published.
            if (box !== target) return@launch
            held[b] = found
            publish()
            Log.i(TAG, "${b.file}: ${found.size} markers nearby in ${System.currentTimeMillis() - began} ms")
        }
    }

    private fun publish() {
        _markers.value = held.values.flatten()
    }

    /** True when the area held still has room around [center] to pan into. */
    private fun wellInside(center: LatLon): Boolean {
        val b = box ?: return false
        return center.lat - b[0] > LAT_PAD / 2 && b[2] - center.lat > LAT_PAD / 2 &&
            center.lon - b[1] > LON_PAD / 2 && b[3] - center.lon > LON_PAD / 2
    }

    // OkHttp asks for gzip and unwraps it, so a plain GET of a .gz
    // object hands back JSON. Reading it as a stream means the file is
    // never a 4 MB string in memory.
    @OptIn(ExperimentalSerializationApi::class)
    private suspend fun load(b: Bundle, box: DoubleArray): List<RoadMarker> = withContext(Dispatchers.IO) {
        val req = Request.Builder().url("$BASE/${b.file}").header("Accept", "application/json").build()
        Backend.http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw BackendError("HTTP ${r.code} for ${b.file}", r.code)
            Backend.json.decodeFromStream(NearbyMarkers(box), r.body.byteStream())
        }
    }
}

/**
 * Reads a snapshot object and keeps only the markers inside a box.
 *
 * The bundles cover the whole country. Decoding one into a list and
 * then filtering it would build several megabytes of objects to throw
 * most of them away, on the very thread time the first paint needs, so
 * each marker is instead decoded from the stream, measured and dropped
 * on the spot. What survives is what the driver can see.
 */
internal class NearbyMarkers(private val box: DoubleArray) : DeserializationStrategy<List<RoadMarker>> {
    private val nearby = Nearby(box)

    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Snapshot") {
        element("markers", nearby.descriptor)
    }

    override fun deserialize(decoder: Decoder): List<RoadMarker> {
        var found: List<RoadMarker> = emptyList()
        val body = decoder.beginStructure(descriptor)
        while (true) {
            when (val i = body.decodeElementIndex(descriptor)) {
                CompositeDecoder.DECODE_DONE -> break
                0 -> found = body.decodeSerializableElement(descriptor, 0, nearby)
                // Every other field is skipped for us, the reader being
                // set to ignore what it does not know.
                else -> throw SerializationException("unexpected field $i in a snapshot")
            }
        }
        body.endStructure(descriptor)
        return found
    }

    private class Nearby(private val box: DoubleArray) : DeserializationStrategy<List<RoadMarker>> {
        override val descriptor: SerialDescriptor = ListSerializer(RoadMarker.serializer()).descriptor

        override fun deserialize(decoder: Decoder): List<RoadMarker> {
            val out = ArrayList<RoadMarker>()
            val items = decoder.beginStructure(descriptor)
            while (true) {
                val i = items.decodeElementIndex(descriptor)
                if (i == CompositeDecoder.DECODE_DONE) break
                val m = items.decodeSerializableElement(descriptor, i, RoadMarker.serializer())
                if (m.lat >= box[0] && m.lon >= box[1] && m.lat <= box[2] && m.lon <= box[3]) out.add(m)
            }
            items.endStructure(descriptor)
            return out
        }
    }
}
