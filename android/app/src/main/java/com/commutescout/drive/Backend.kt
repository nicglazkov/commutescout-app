package com.commutescout.drive

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/** Everything the app talks to lives at commutescout.com; no keys ship in the app. */
object Backend {
    const val BASE = "https://commutescout.com"
    const val NAV_ROUTE_URL = "$BASE/api/nav/route"
    const val STYLE_URL = "$BASE/api/tiles/style.json"
    const val TRAFFIC_TILES = "$BASE/api/traffictile/{z}/{x}/{y}.png"

    /** The base map: light, dark or outdoors, all through the proxy. */
    fun styleUrl(style: String) = "$STYLE_URL?style=$style"

    /** The website page focused on a spot, the same link the site shares. */
    fun mapUrl(lat: Double, lon: Double, kind: String? = null): String =
        "$BASE/map?focus=%.5f,%.5f".format(lat, lon) + (kind?.let { "&k=$it" } ?: "")

    val http: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(20, TimeUnit.SECONDS)
        .build()

    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    suspend inline fun <reified T> get(path: String, query: Map<String, String>): T = withContext(Dispatchers.IO) {
        val q = query.entries.joinToString("&") { (k, v) -> "$k=" + URLEncoder.encode(v, "UTF-8") }
        val req = Request.Builder().url("$BASE$path?$q").header("Accept", "application/json").build()
        http.newCall(req).execute().use { r ->
            if (!r.isSuccessful) throw BackendError("HTTP ${r.code} for $path", r.code)
            json.decodeFromString<T>(r.body.string())
        }
    }
}

/** A refused request; [code] is the HTTP status when there was one, else 0. */
class BackendError(message: String, val code: Int = 0) : Exception(message)

@Serializable
data class Suggestion(val name: String, val lat: Double, val lon: Double)

@Serializable
private data class SuggestResponse(val suggestions: List<Suggestion> = emptyList())

@Serializable
private data class GeocodeResponse(val candidates: List<Suggestion> = emptyList())

/** Places and addresses, through the same endpoints as the website. */
object Search {
    suspend fun suggest(q: String, near: Pair<Double, Double>?): List<Suggestion> {
        val query = mutableMapOf("q" to q, "limit" to "6")
        near?.let { query["lat"] = "%.5f".format(it.first); query["lon"] = "%.5f".format(it.second) }
        return Backend.get<SuggestResponse>("/api/suggest", query).suggestions
    }

    suspend fun geocode(q: String): List<Suggestion> =
        Backend.get<GeocodeResponse>("/api/geocode", mapOf("q" to q, "limit" to "5")).candidates
}

/** One price band on a toll corridor: what an entry point costs to use. */
@Serializable
data class TollEntry(
    val label: String? = null,
    /** Each row is [entry name, price]; the server sends a mixed array. */
    val rows: List<JsonArray> = emptyList(),
) {
    /** The rows as text and dollars, skipping anything malformed. */
    val prices: List<Pair<String, Double>>
        get() = rows.mapNotNull { r ->
            if (r.size < 2) null else {
                val name = (r[0] as? JsonPrimitive)?.content ?: return@mapNotNull null
                val price = (r[1] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: return@mapNotNull null
                name to price
            }
        }
}

/**
 * One thing on the road. The website's nine marker kinds all arrive in
 * this one shape, because the server builds the map endpoint and the
 * snapshot publisher from the same function: incidents, closures, chain
 * controls, wildfires, community reports, toll prices, cameras, message
 * signs and roadside weather stations.
 */
@Serializable
data class RoadMarker(
    val kind: String,
    val lat: Double,
    val lon: Double,
    val id: String? = null,
    val type: String? = null,
    val cls: String? = null,
    val label: String? = null,
    val location: String? = null,
    val route: String? = null,
    val status: String? = null,
    val name: String? = null,
    val flare_kind: String? = null,
    val source: String? = null,
    val description: String? = null,
    val area: String? = null,
    val dir: String? = null,
    val reported: String? = null,
    val county: String? = null,
    val delay_min: Double? = null,
    val lanes: String? = null,
    val since: Long? = null,      // epoch seconds
    val until: Long? = null,
    val work: String? = null,
    val facility: String? = null,
    val tier: String? = null,          // approved, unreviewed or private, for plugin markers
    val acres: Double? = null,         // wildfires
    val contained: Double? = null,     // wildfires, percent
    val discovered: String? = null,    // wildfires, ISO time
    val updated: String? = null,
    val src: String? = null,           // the agency behind a roadside marker
    // Closure and toll geometry. The endpoint sends it; the snapshot
    // drops it, so a marker can arrive with a dot and no line.
    val path: List<List<Double>>? = null,             // closure stretch, [lat, lon] pairs
    val segs: List<List<List<Double>>>? = null,       // toll corridor, one list per segment
    // A burn footprint ships either as one ring of [lat, lon] pairs or
    // as a list of rings, so it is read loosely and normalised below.
    val poly: JsonElement? = null,
    // Cameras.
    val direction: String? = null,
    val near: String? = null,
    val image: String? = null,
    val stream: String? = null,
    // Message signs.
    val message: String? = null,
    val lines: List<String>? = null,
    val blank: Boolean? = null,
    // Roadside weather stations. Temperatures Celsius, wind mph,
    // visibility metres, humidity percent.
    val station: String? = null,
    val air_c: Double? = null,
    val pave_c: Double? = null,
    val wind: Double? = null,
    val gust: Double? = null,
    val wind_dir: Double? = null,
    val vis_m: Double? = null,
    val rh: Double? = null,
    val precip: String? = null,
    val surface: String? = null,
    // Toll prices.
    val corridor: String? = null,
    val min: Double? = null,
    val max: Double? = null,
    val n: Int? = null,
    val pricing: String? = null,        // live or fixed
    val toll_type: String? = null,      // express or required
    val toll_dir: String? = null,
    val toll_note: String? = null,
    val as_of: String? = null,
    val gp_min: Double? = null,         // minutes in the regular lanes
    val lane_min: Double? = null,       // minutes in the express lanes
    val entries: List<TollEntry>? = null,
) {
    val key: String get() = "$kind:${id ?: "%.4f,%.4f".format(lat, lon)}"

    /** Fires too small or too contained to announce on a drive. */
    val tooMinorToAnnounce: Boolean get() = kind == "wildfire" && ((contained ?: 0.0) >= 90 || (acres != null && acres < 10))

    /**
     * The mapped burn footprint, one list of points per lobe. A fire
     * with several lobes keeps them apart: joining them would draw a
     * line across the untouched ground between them.
     */
    val perimeter: List<List<LatLon>>
        get() {
            val rings = poly as? JsonArray ?: return emptyList()
            val first = rings.firstOrNull() as? JsonArray ?: return emptyList()
            // One ring of [lat, lon] pairs, or a list of such rings.
            val many = if (first.firstOrNull() is JsonArray) rings.mapNotNull { it as? JsonArray } else listOf(rings)
            return many.map { ring -> ring.mapNotNull { point(it) } }.filter { it.size >= 3 }
        }

    /** The stretch of road a closure covers, empty when only a dot arrived. */
    val stretch: List<LatLon> get() = path.orEmpty().mapNotNull { pair(it) }

    /** A toll corridor, one list of points per segment of carriageway. */
    val corridorLines: List<List<LatLon>>
        get() = segs.orEmpty().map { seg -> seg.mapNotNull { pair(it) } }.filter { it.size >= 2 }

    /** The sign's board, split out of the message when the server did not. */
    val signLines: List<String>
        get() = lines?.takeIf { it.isNotEmpty() }
            ?: message?.takeIf { it.isNotBlank() }?.split(" / ")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: emptyList()

    /** Route and direction as one phrase, for roadside markers. */
    val roadLine: String?
        get() = listOfNotNull(route, direction).filter { it.isNotBlank() }.joinToString(" ").takeIf { it.isNotEmpty() }

    /** The toll now, as a range when the price varies by entry point. */
    val tollRange: String?
        get() {
            val low = min ?: return null
            val high = max ?: low
            return if (low == high) money(low) else "${money(low)} to ${money(high)}"
        }

    private fun money(v: Double): String = if (v == Math.floor(v)) "$%.0f".format(v) else "$%.2f".format(v)

    private fun point(e: JsonElement): LatLon? = (e as? JsonArray)?.let { pair(it.mapNotNull { v -> (v as? JsonPrimitive)?.content?.toDoubleOrNull() }) }

    private fun pair(v: List<Double>): LatLon? = if (v.size >= 2) LatLon(v[0], v[1]) else null

    /** The lines under the title in the marker card. */
    val detailLines: List<String>
        get() {
            val out = mutableListOf<String>()
            when (kind) {
                "incident" -> {
                    location?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                    listOfNotNull(dir, area).filter { it.isNotBlank() }.joinToString(", ").takeIf { it.isNotEmpty() }?.let { out.add(it) }
                    reported?.let { out.add("Reported " + whenText(it)) }
                }
                "lane_closure" -> {
                    lanes?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                    work?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                    listOfNotNull(since?.let { "from " + whenEpoch(it) }, until?.let { "until " + whenEpoch(it) })
                        .joinToString(" ").takeIf { it.isNotEmpty() }?.let { out.add(it) }
                    delay_min?.takeIf { it > 0 }?.let { out.add("Expect about ${it.toInt()} min of delay") }
                    county?.takeIf { it.isNotBlank() }?.let { out.add("$it County") }
                }
                "chain_control" -> location?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                "wildfire" -> {
                    county?.takeIf { it.isNotBlank() }?.let { out.add("$it County") }
                    (reported ?: discovered)?.let { out.add("Updated " + whenText(it)) }
                }
                "camera", "sign" -> {
                    roadLine?.let { out.add(it) }
                    near?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                }
                "rwis" -> route?.takeIf { it.isNotBlank() }?.let { out.add(it) }
                "toll" -> {
                    corridor?.takeIf { it.isNotBlank() && it != name }?.let { out.add(it) }
                    toll_dir?.takeIf { it.isNotBlank() }?.let {
                        out.add(listOfNotNull(it.replaceFirstChar { c -> c.uppercase() }, toll_note?.takeIf { n -> n.isNotBlank() }).joinToString(", "))
                    }
                }
                "plugin" -> {
                    source?.takeIf { it.isNotBlank() }?.let {
                        val badge = when (tier) { "approved" -> " (approved by CommuteScout)"; "private" -> " (your private plugin)"; else -> " (public, not reviewed)" }
                        out.add("Community report via $it$badge")
                    }
                    reported?.let { out.add(whenText(it)) }
                }
            }
            return out
        }

    /** A shareable link to this spot on the website. */
    val webUrl: String get() = Backend.mapUrl(lat, lon, kind)

    private fun whenEpoch(epoch: Long): String = android.text.format.DateUtils.getRelativeTimeSpanString(
        epoch * 1000, System.currentTimeMillis(), android.text.format.DateUtils.MINUTE_IN_MILLIS).toString()

    private fun whenText(iso: String): String = runCatching {
        val t = java.time.OffsetDateTime.parse(iso).toInstant().toEpochMilli()
        android.text.format.DateUtils.getRelativeTimeSpanString(t, System.currentTimeMillis(),
            android.text.format.DateUtils.MINUTE_IN_MILLIS).toString()
    }.getOrDefault(iso)

    /** Short text for the strip and for speech. Kinds match the web map's markers. */
    val displayTitle: String
        get() = when (kind) {
            "incident" -> label ?: type ?: "Incident"
            "lane_closure" -> label ?: "Lane closure"
            "chain_control" -> "Chain control ${status ?: ""} on ${route ?: ""}".trim()
            "wildfire" -> "${name ?: "Wildfire"} Fire"
            "plugin" -> description ?: (flare_kind ?: "Report").replace('_', ' ').replaceFirstChar { it.uppercase() }
            "camera" -> name ?: "Roadside camera"
            "sign" -> roadLine ?: "Message sign"
            "rwis" -> station ?: name ?: "Weather station"
            "toll" -> label ?: name ?: corridor ?: "Toll"
            else -> label ?: kind
        }

    val spokenTitle: String get() = displayTitle.replace("@", "at").replace("(", "").replace(")", "")

    /** How far from the route a marker still counts as being on it. */
    val corridorMeters: Double
        get() = when (kind) {
            "chain_control" -> 1000.0
            // A fire matters at a distance only when it is big.
            "wildfire" -> if ((acres ?: 0.0) >= 1000) 5000.0 else if ((acres ?: 0.0) >= 100) 3000.0 else 1500.0
            else -> 300.0
        }
}

@Serializable
private data class MapData(val markers: List<RoadMarker> = emptyList())

object LiveData {
    /**
     * The kinds a driver is warned about on a trip. Roadside
     * information is not an alert: a camera or a message sign is
     * something to look at, not something to announce.
     */
    const val KINDS = "incident,closure,chain,fire,plugin"

    /**
     * Every kind the map draws, in the query names /api/mapdata takes.
     * Three of them do not match the kind the server emits: closure
     * returns lane_closure, chain returns chain_control and fire
     * returns wildfire. The other six are the same word on both sides.
     */
    const val MAP_KINDS = "incident,closure,chain,fire,plugin,toll,camera,sign,rwis"

    suspend fun markers(south: Double, west: Double, north: Double, east: Double, kinds: String = KINDS): List<RoadMarker> =
        Backend.get<MapData>(
            "/api/mapdata",
            mapOf("bbox" to "%.4f,%.4f,%.4f,%.4f".format(south, west, north, east), "kinds" to kinds),
        ).markers
}
