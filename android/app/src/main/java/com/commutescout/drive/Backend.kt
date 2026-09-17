package com.commutescout.drive

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
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
            if (!r.isSuccessful) throw BackendError("HTTP ${r.code} for $path")
            json.decodeFromString<T>(r.body.string())
        }
    }
}

class BackendError(message: String) : Exception(message)

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

/** One thing on the road: an incident, closure, chain control, fire or a community report. */
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
) {
    val key: String get() = "$kind:${id ?: "%.4f,%.4f".format(lat, lon)}"

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
                    reported?.let { out.add("Updated " + whenText(it)) }
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
            else -> label ?: kind
        }

    val spokenTitle: String get() = displayTitle.replace("@", "at").replace("(", "").replace(")", "")

    /** How far from the route a marker still counts as being on it. */
    val corridorMeters: Double
        get() = when (kind) {
            "chain_control" -> 1000.0
            "wildfire" -> 12000.0
            else -> 300.0
        }
}

@Serializable
private data class MapData(val markers: List<RoadMarker> = emptyList())

object LiveData {
    const val KINDS = "incident,closure,chain,fire,plugin"

    suspend fun markers(south: Double, west: Double, north: Double, east: Double, kinds: String = KINDS): List<RoadMarker> =
        Backend.get<MapData>(
            "/api/mapdata",
            mapOf("bbox" to "%.4f,%.4f,%.4f,%.4f".format(south, west, north, east), "kinds" to kinds),
        ).markers
}
