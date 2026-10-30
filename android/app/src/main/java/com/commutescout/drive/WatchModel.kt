package com.commutescout.drive

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/*
 * Watch areas as the backend keeps them (watch.py): a circle (center
 * and radius_km), a route (points and buffer_km) or a polygon (points),
 * with the kinds it alerts on, its channels, whether it follows the
 * account's quiet hours, and what is happening in it right now (live).
 * Every field past id is optional: an older server leaves the newer
 * ones out and the screen simply shows less.
 */

@Serializable
data class Watch(
    val id: String,
    val name: String? = null,
    val type: String? = null,
    val center: Center? = null,
    val radius_km: Double? = null,
    val kinds: List<String>? = null,
    val active: Boolean? = null,
    /** [{lat, lon}] as stored, or [[lat, lon]] from an older server. */
    val points: JsonElement? = null,
    val buffer_km: Double? = null,
    val length_km: Double? = null,
    val channels: Channels? = null,
    val quiet_hours: Boolean? = null,
    val live: Live? = null,
) {
    @Serializable data class Center(val lat: Double, val lon: Double)
    @Serializable data class Channels(val push: Boolean? = null, val email: Boolean? = null)
    @Serializable data class Top(val kind: String? = null, val title: String? = null, val body: String? = null)
    @Serializable data class Live(
        val count: Int = 0,
        val by_kind: Map<String, Int>? = null,
        val top: Top? = null,
        val quiet_since: String? = null,
        val updated_at: String? = null,
    )

    val shape: String get() = when (type) { "route" -> "route"; "polygon" -> "polygon"; else -> "circle" }

    /** The route's or polygon's points, whichever way the server wrote them. */
    val path: List<LatLon> get() = (points as? JsonArray)?.mapNotNull { p ->
        when (p) {
            is JsonObject -> {
                val lat = (p["lat"] as? JsonPrimitive)?.doubleOrNull; val lon = (p["lon"] as? JsonPrimitive)?.doubleOrNull
                if (lat != null && lon != null) LatLon(lat, lon) else null
            }
            is JsonArray -> {
                val lat = (p.getOrNull(0) as? JsonPrimitive)?.doubleOrNull; val lon = (p.getOrNull(1) as? JsonPrimitive)?.doubleOrNull
                if (lat != null && lon != null) LatLon(lat, lon) else null
            }
            else -> null
        }
    } ?: emptyList()
}

@Serializable
data class QuietHours(
    val enabled: Boolean = false,
    val start: String = "22:00",
    val end: String = "06:00",
    val tz: String = "America/Los_Angeles",
    val summary: Boolean = true,
)

@Serializable
data class WatchPrefs(
    val units: String? = null,
    val alerts_push: Boolean? = null,
    val alerts_email: Boolean? = null,
    val notify_clears: Boolean? = null,
    val quiet_hours: QuietHours? = null,
)

@Serializable
data class MeResponse(
    val email: String? = null,
    val status: String? = null,
    val prefs: WatchPrefs? = null,
    val watches: List<Watch> = emptyList(),
)

@Serializable data class PrefsResponse(val prefs: WatchPrefs? = null)

/** A watch area's kinds: the backend id, the label, the icon and its color. */
enum class WatchKind(val id: String, val label: String, val icon: String, val tone: com.commutescout.drive.design.Tone) {
    INCIDENT("incident", "Incidents", "crash", com.commutescout.drive.design.Tone.HIGH),
    CLOSURE("closure", "Closures", "closure", com.commutescout.drive.design.Tone.HIGH),
    CHAIN("chain", "Chain controls", "chain", com.commutescout.drive.design.Tone.MID),
    FIRE("fire", "Wildfires", "fire", com.commutescout.drive.design.Tone.HIGH);

    companion object {
        val ids = entries.map { it.id }
        fun of(id: String?) = entries.firstOrNull { it.id == id }
    }
}

/** A new or edited watch area, before it goes to the server. */
data class WatchDraft(
    val name: String,
    val shape: String,               // circle, route or polygon
    val center: LatLon? = null,
    val radiusMi: Int = 8,
    val points: List<LatLon> = emptyList(),
    val kinds: Set<String> = setOf("incident", "closure", "fire"),
    val quiet: Boolean = true,
    val push: Boolean = true,
    val email: Boolean = false,
)

/** How a watch card's status line reads, and in which color. */
data class WatchStatus(val text: String, val tone: com.commutescout.drive.design.Tone, val live: Boolean)

object WatchText {
    private val clock = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

    /** "22:00" as "10:00 PM". */
    fun time(hhmm: String): String = runCatching { LocalTime.parse(hhmm.padStart(5, '0')).format(clock) }.getOrDefault(hhmm)

    fun quietLine(q: QuietHours?): String = when {
        q == null || !q.enabled -> "Off"
        q.summary -> "${time(q.start)} to ${time(q.end)}, then one summary"
        else -> "${time(q.start)} to ${time(q.end)}"
    }

    fun status(w: Watch, zone: ZoneId = ZoneId.systemDefault()): WatchStatus? {
        if (w.active == false) return WatchStatus("Paused", com.commutescout.drive.design.Tone.CLEAR, false)
        val live = w.live ?: return null
        if (live.count <= 0) {
            val since = live.quiet_since?.let { s -> runCatching { Instant.parse(s).atZone(zone).toLocalTime().format(clock) }.getOrNull() }
            return WatchStatus(if (since != null) "Quiet since $since" else "Quiet now", com.commutescout.drive.design.Tone.GOOD, false)
        }
        val top = live.top
        val tone = when (top?.kind) { "chain", "closure" -> com.commutescout.drive.design.Tone.MID; else -> com.commutescout.drive.design.Tone.HIGH }
        val title = top?.title?.trim().orEmpty()
        val text = when {
            live.count == 1 && title.isNotEmpty() -> title
            live.count == 1 -> "1 ${noun(top?.kind, 1)} now"
            else -> "${live.count} alerts now"
        }
        return WatchStatus(text, tone, true)
    }

    private fun noun(kind: String?, n: Int): String = when (kind) {
        "incident" -> "incident"; "closure" -> "closure"; "chain" -> "chain control"; "fire" -> "wildfire"; else -> "alert"
    } + if (n == 1) "" else "s"

    /** "8 mi around Home", "Your drive to Work, 2 mi each side", "Your own shape, about 120 sq mi". */
    fun meta(w: Watch, home: LatLon?, work: LatLon?): String {
        fun near(a: LatLon?, b: LatLon?) = a != null && b != null && WatchGeo.haversineKm(a, b) < 0.5
        val side = "${WatchGeo.miles(w.buffer_km ?: WatchGeo.ROUTE_BUFFER_KM)} mi each side"
        return when (w.shape) {
            "route" -> {
                val p = w.path
                when {
                    p.size >= 2 && near(p.first(), home) && near(p.last(), work) -> "Your drive to Work, $side"
                    p.size >= 2 && near(p.first(), work) && near(p.last(), home) -> "Your drive home, $side"
                    else -> "A ${WatchGeo.miles(w.length_km ?: WatchGeo.lengthKm(p))} mi drive, $side"
                }
            }
            "polygon" -> "Your own shape, about ${WatchGeo.grouped(WatchGeo.polygonSqMi(w.path))} sq mi"
            else -> {
                val r = WatchGeo.radiusMi(w.radius_km)
                val c = w.center?.let { LatLon(it.lat, it.lon) }
                when {
                    near(c, home) -> "$r mi around Home"
                    near(c, work) -> "$r mi around Work"
                    else -> "$r mi around a point you chose"
                }
            }
        }
    }
}

/** The bodies the watch endpoints take. */
object WatchBodies {
    private fun pairs(points: List<LatLon>) = buildJsonArray {
        points.forEach { add(buildJsonArray { add(JsonPrimitive(it.lat)); add(JsonPrimitive(it.lon)) }) }
    }
    private fun kinds(k: Set<String>) = buildJsonArray { WatchKind.ids.filter { it in k }.forEach { add(JsonPrimitive(it)) } }

    fun create(d: WatchDraft): String = buildJsonObject {
        put("name", d.name.trim().ifEmpty { "Watch area" }.take(60))
        put("kinds", kinds(d.kinds))
        put("channels", buildJsonObject { put("push", d.push); put("email", d.email) })
        put("quiet_hours", d.quiet)
        when (d.shape) {
            "route" -> { put("type", "route"); put("points", pairs(WatchGeo.thin(d.points))); put("buffer_km", WatchGeo.ROUTE_BUFFER_KM) }
            "polygon" -> { put("type", "polygon"); put("points", pairs(d.points)) }
            else -> {
                put("type", "circle")
                val c = d.center ?: LatLon(0.0, 0.0)
                put("center", buildJsonObject { put("lat", c.lat); put("lon", c.lon) })
                put("radius_km", WatchGeo.radiusKm(d.radiusMi))
            }
        }
    }.toString()

    /** What changed on an existing watch; circles and routes keep their geometry (the server's rule). */
    fun update(d: WatchDraft): String = buildJsonObject {
        put("name", d.name.trim().ifEmpty { "Watch area" }.take(60))
        put("kinds", kinds(d.kinds))
        put("quiet_hours", d.quiet)
        if (d.shape == "polygon") put("points", pairs(d.points))
    }.toString()

    fun prefs(push: Boolean? = null, email: Boolean? = null, clears: Boolean? = null, quiet: QuietHours? = null): String = buildJsonObject {
        push?.let { put("alerts_push", it) }
        email?.let { put("alerts_email", it) }
        clears?.let { put("notify_clears", it) }
        quiet?.let { q -> put("quiet_hours", buildJsonObject {
            put("enabled", q.enabled); put("start", q.start); put("end", q.end); put("tz", q.tz); put("summary", q.summary)
        }) }
    }.toString()

    fun channels(push: Boolean, email: Boolean): String =
        buildJsonObject { put("channels", buildJsonObject { put("push", push); put("email", email) }) }.toString()

    /** The server's {"error": "..."} as words a person can read. */
    fun error(status: Int, text: String): String = when (status) {
        0 -> OfflineText.RETRY
        401 -> "Sign in again to change your watch areas."
        else -> runCatching { Backend.json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()
            ?.replaceFirstChar { it.uppercase() }?.let { if (it.endsWith(".")) it else "$it." }
            ?: "The server could not save that ($status). Try again."
    }
}
