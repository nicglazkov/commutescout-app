package com.commutescout.drive

import android.util.Log
import kotlinx.coroutines.CancellationException
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
import java.io.FilterInputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.Deflater
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

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

    /**
     * The whole country is held, so zooming out never empties the map:
     * about 19,000 markers with the default layers, 36,000 with cameras,
     * which the phone draws without trouble. Markers outside it (a
     * plugin's test alert abroad) are dropped on read.
     */
    private val COUNTRY = doubleArrayOf(17.0, -170.0, 72.0, -65.0)

    /** A held bundle is re-read at this age, so signs and prices stay live. */
    private const val MAX_AGE_MS = 300_000L

    /**
     * A bundle that failed, or that came from the copy saved on the
     * phone, is tried again this soon rather than on every location fix.
     */
    private const val RETRY_MS = 30_000L

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
    /** When each held bundle was current, and which ones came from the saved copy. */
    private val asOfMs = HashMap<Bundle, Long>()
    private val fromDisk = HashSet<Bundle>()
    private val _asOf = MutableStateFlow<Long?>(null)

    /** How new the live bundle is: shown in the offline banner, and what expiry is measured from. */
    val asOf = _asOf.asStateFlow()
    private val jobs = HashMap<Bundle, Job>()
    private var wanted = setOf(Bundle.LIVE)
    private var box: DoubleArray? = null

    // One thread of its own, never the main one. Launch is the busiest
    // the main thread ever is, between starting the map and drawing the
    // first frame, and work posted to it there waits for all of that to
    // finish. Measured on an emulator, that wait was twelve seconds:
    // longer than the fetch it was delaying. Everything here runs on
    // this one thread instead, which also keeps the bookkeeping below
    // free of locks.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private var ticker: Job? = null

    /**
     * Point the snapshots at a place and start loading. Called with the
     * last known position at launch, again with the first live fix, and
     * again whenever the driver leaves the middle of the held area.
     */
    fun prime(center: LatLon?) {
        scope.launch { primeNow(center) }
    }

    /**
     * Hold exactly the bundles the switched-on layers need. A layer
     * switched off frees its markers; one switched back on loads again.
     */
    fun sync(bundles: Set<Bundle>) {
        scope.launch { syncNow(bundles) }
    }

    private fun primeNow(center: LatLon?) {
        if (box == null) box = COUNTRY
        // Remembered so the next launch opens where the phone was.
        if (center != null) runCatching { Engine.prefs.lastCenter = center }
        syncNow(wanted)
        if (ticker == null) ticker = scope.launch {
            while (isActive) { delay(MAX_AGE_MS); if (Engine.awake()) syncNow(wanted) }
        }
    }

    private fun syncNow(bundles: Set<Bundle>) {
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
        // The saved copy stands in only when nothing better is held: a
        // bundle already fetched this session is newer than any file.
        val allowSaved = held[b] == null
        jobs[b] = scope.launch {
            val began = System.currentTimeMillis()
            val found = runCatching { load(b, target, allowSaved) }.getOrElse { e ->
                if (e is CancellationException) throw e
                Log.w(TAG, "${b.file} did not load (${e.message})")
                loadedAt[b] = System.currentTimeMillis() - MAX_AGE_MS + RETRY_MS
                return@launch
            }
            // The area can move while a bundle is in flight; a reply for
            // an area the driver already left is not published.
            if (box !== target) return@launch
            held[b] = found.markers
            asOfMs[b] = found.asOf
            if (found.saved) {
                fromDisk.add(b)
                loadedAt[b] = System.currentTimeMillis() - MAX_AGE_MS + RETRY_MS
            } else fromDisk.remove(b)
            publish()
            Log.i(TAG, "${b.file}: ${found.markers.size} markers nearby in ${System.currentTimeMillis() - began} ms" +
                if (found.saved) ", from the copy saved at ${OfflineText.time(found.asOf)}" else "")
        }
    }

    /** The signal is back: anything that failed or came from the saved copy is fetched now. */
    fun reconnected() {
        scope.launch {
            for (b in wanted) if (b in fromDisk || held[b] == null) { jobs.remove(b)?.cancel(); loadedAt.remove(b) }
            syncNow(wanted)
        }
    }

    private fun publish() {
        _markers.value = held.values.flatten()
        _asOf.value = asOfMs[Bundle.LIVE] ?: asOfMs.values.maxOrNull()
    }

    private class Loaded(val markers: List<RoadMarker>, val asOf: Long, val saved: Boolean)

    // OkHttp asks for gzip and unwraps it, so a plain GET of a .gz
    // object hands back JSON. Reading it as a stream means the file is
    // never a 4 MB string in memory.
    //
    // The same bytes are written to the phone as they are read, gzipped
    // at the fastest level, so the next launch without a signal has the
    // last good copy. Only a complete download replaces the saved one.
    @OptIn(ExperimentalSerializationApi::class)
    private suspend fun load(b: Bundle, box: DoubleArray, allowSaved: Boolean): Loaded = withContext(Dispatchers.IO) {
        val file = OfflineStore.cache("snapshot-${b.name.lowercase()}.json.gz")
        try {
            val req = Request.Builder().url("$BASE/${b.file}").header("Accept", "application/json").build()
            Backend.http.newCall(req).execute().use { r ->
                if (!r.isSuccessful) throw BackendError("HTTP ${r.code} for ${b.file}", r.code)
                var found: List<RoadMarker> = emptyList()
                OfflineStore.write(file) { raw ->
                    object : GZIPOutputStream(raw) { init { def.setLevel(Deflater.BEST_SPEED) } }.use { gz ->
                        val tee = TeeInputStream(r.body.byteStream(), gz)
                        found = Backend.json.decodeFromStream(NearbyMarkers(box), tee)
                        tee.drain()
                    }
                }
                Loaded(found, System.currentTimeMillis(), false)
            }
        } catch (e: Exception) {
            if (e is CancellationException || !allowSaved) throw e
            val age = System.currentTimeMillis() - file.lastModified()
            if (!file.exists() || age > ShelfLife.MAX_AGE_MS) throw e
            val saved = GZIPInputStream(file.inputStream().buffered()).use { Backend.json.decodeFromStream(NearbyMarkers(box), it) }
            Log.i(TAG, "${b.file}: no answer (${e.message}), using the copy saved ${age / 1000} s ago")
            Loaded(ShelfLife.prune(saved, file.lastModified()), file.lastModified(), true)
        }
    }
}

/** Copies everything read through it to [copy]: the download and the saved file in one pass. */
private class TeeInputStream(source: InputStream, private val copy: OutputStream) : FilterInputStream(source) {
    override fun read(): Int = super.read().also { if (it >= 0) copy.write(it) }

    override fun read(b: ByteArray, off: Int, len: Int): Int =
        super.read(b, off, len).also { if (it > 0) copy.write(b, off, it) }

    override fun skip(n: Long): Long {
        val buf = ByteArray(8192)
        var left = n
        while (left > 0) {
            val r = read(buf, 0, minOf(buf.size.toLong(), left).toInt())
            if (r < 0) break
            left -= r
        }
        return n - left
    }

    /** Whatever the reader left unread still belongs in the copy. */
    fun drain() {
        val buf = ByteArray(8192)
        while (read(buf, 0, buf.size) >= 0) Unit
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
