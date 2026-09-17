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
) {
    val key: String get() = "$kind:${id ?: "%.4f,%.4f".format(lat, lon)}"

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

    suspend fun markers(south: Double, west: Double, north: Double, east: Double): List<RoadMarker> =
        Backend.get<MapData>(
            "/api/mapdata",
            mapOf("bbox" to "%.4f,%.4f,%.4f,%.4f".format(south, west, north, east), "kinds" to KINDS),
        ).markers
}
