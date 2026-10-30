package com.commutescout.drive

import kotlinx.serialization.Serializable
import java.net.URI
import java.net.URLDecoder
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Watch alerts and the map name the same four kinds differently: a
 * watch says closure, chain and fire where the map says lane_closure,
 * chain_control and wildfire. Old alert links carry the watch word,
 * which is why a tapped alert used to find only incidents.
 */
object EventKinds {
    /** The map's marker kind for either naming, or null for anything else. */
    fun markerKind(kind: String?): String? = when (kind?.trim()?.lowercase()) {
        "incident" -> "incident"
        "closure", "lane_closure" -> "lane_closure"
        "chain", "chain_control" -> "chain_control"
        "fire", "wildfire" -> "wildfire"
        else -> null
    }

    /** What the status banner calls one of these, in a sentence. */
    fun noun(markerKind: String?): String = when (markerKind) {
        "incident" -> "incident"
        "lane_closure" -> "closure"
        "chain_control" -> "chain control"
        "wildfire" -> "wildfire"
        else -> "event"
    }

    /** The /api/mapdata query word for a marker kind (the reverse of [markerKind]). */
    fun queryKind(markerKind: String): String = when (markerKind) {
        "lane_closure" -> "closure"
        "chain_control" -> "chain"
        "wildfire" -> "fire"
        else -> markerKind
    }
}

/**
 * A tapped watch alert: what the push said, before anything is known
 * about the event now.
 *
 * A push arrives one of two ways. With the app in the foreground,
 * [PushService] draws it and copies the data keys onto the intent;
 * in the background the system draws it and puts the same keys on the
 * launch intent itself. Pushes sent before the server added the event
 * keys carry only the map link, which still names the spot and a kind.
 */
data class AlertTap(
    val eventId: String?,
    /** The map's marker kind, or null when the push did not say. */
    val kind: String?,
    val lat: Double,
    val lon: Double,
    val title: String?,
    val body: String?,
    /** The watch area's name, "Home area". */
    val watch: String?,
    /** When the server sent it, epoch seconds. */
    val sentAt: Long?,
    /** "cleared" on the follow-up push that says the event is over. */
    val status: String? = null,
    /** How the lanes sat, when the push carried them. */
    val laneLayout: LaneLayout? = null,
) {
    companion object {
        /**
         * The alert in a push's data keys, or null when they do not name
         * a place. `csUrl` is the key the app's own notification used
         * before the event keys existed; `url` is the server's.
         */
        fun parse(data: Map<String, String?>): AlertTap? {
            val link = (data["url"] ?: data["csUrl"])?.takeIf { it.isNotBlank() }?.let { linkParts(it) }
            val lat = data["event_lat"]?.toDoubleOrNull() ?: link?.lat ?: return null
            val lon = data["event_lon"]?.toDoubleOrNull() ?: link?.lon ?: return null
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
            return AlertTap(
                eventId = data["event_id"]?.takeIf { it.isNotBlank() },
                kind = EventKinds.markerKind(data["event_kind"]) ?: EventKinds.markerKind(link?.kind),
                lat = lat, lon = lon,
                title = data["event_title"]?.takeIf { it.isNotBlank() },
                body = data["event_body"]?.takeIf { it.isNotBlank() },
                watch = data["event_watch"]?.takeIf { it.isNotBlank() },
                sentAt = data["event_sent_at"]?.toDoubleOrNull()?.toLong(),
                status = data["event_status"]?.trim()?.lowercase()?.takeIf { it.isNotEmpty() },
                // FCM data values are strings: the layout rides as JSON text.
                laneLayout = data["event_lane_layout"]?.takeIf { it.isNotBlank() }
                    ?.let { runCatching { kotlinx.serialization.json.Json.parseToJsonElement(it) }.getOrNull() }?.let { LaneLayout.from(it) },
            )
        }

        private data class Link(val lat: Double, val lon: Double, val kind: String?)

        /** focus=LAT,LON and k=KIND out of a map link. */
        /**
         * A summary push ("3 new alerts in Home area") has no one spot to
         * show: it links to the watch page, so the app opens watch areas.
         */
        fun opensWatchAreas(data: Map<String, String?>): Boolean {
            if (data["event_kind"]?.trim()?.lowercase() == "summary") return true
            val url = (data["url"] ?: data["csUrl"])?.trim()?.takeIf { it.isNotEmpty() } ?: return false
            val path = runCatching { URI(url).path }.getOrNull()?.trimEnd('/') ?: return false
            return path.endsWith("/watch") && linkParts(url) == null
        }

        private fun linkParts(url: String): Link? {
            val query = runCatching { URI(url.trim()).rawQuery }.getOrNull() ?: return null
            val params = query.split("&").mapNotNull { pair ->
                val i = pair.indexOf('=')
                if (i <= 0) null else pair.substring(0, i) to runCatching { URLDecoder.decode(pair.substring(i + 1), "UTF-8") }.getOrDefault("")
            }.toMap()
            val f = params["focus"]?.split(",")?.mapNotNull { it.trim().toDoubleOrNull() } ?: return null
            if (f.size < 2) return null
            return Link(f[0], f[1], params["k"])
        }
    }
}

/** What became of an alerted event, as the status banner says it. */
enum class EventState { LOADING, ACTIVE, CHANGED, CLEARED, GONE, UNKNOWN }

/** The banner over the event sheet. */
data class EventStatus(
    val state: EventState,
    /** When the state was learned, epoch ms. */
    val checkedAt: Long? = null,
    /** When the event cleared, epoch ms, for [EventState.CLEARED]. */
    val clearedAt: Long? = null,
    /** What a changed event says now. */
    val newTitle: String? = null,
    /** Active only because the map still has it: the server did not answer. */
    val unconfirmed: Boolean = false,
    /** The same kind still reported at the spot after a clear: not the alerted one. */
    val nearby: RoadMarker? = null,
)

/**
 * The open event sheet. [marker] is what the body describes; it is
 * null when the alert's event has no marker any more, and the body then
 * shows what the alert said. [alert] is set when a notification opened
 * it; [status] is the banner, null for an ordinary tap on the map.
 */
data class EventSheet(
    val marker: RoadMarker?,
    val alert: AlertTap? = null,
    val status: EventStatus? = null,
    /** When [marker] was put in the sheet, epoch ms: only a refresh after it can drop it. */
    val shownAt: Long = 0L,
)

/** /api/event-status, as the server answers it. */
@Serializable
data class EventStatusAnswer(
    val id: String? = null,
    val kind: String? = null,
    val checked_at: String? = null,
    val state: String = "",
    val cleared_at: String? = null,
    val event: AlertedEvent? = null,
    val marker: RoadMarker? = null,
    val nearby: RoadMarker? = null,
)

/** The event as the server knows it; for a changed event, the new one. */
@Serializable
data class AlertedEvent(val title: String? = null, val body: String? = null, val lat: Double? = null, val lon: Double? = null)

/** /api/incident/{id}: only the part the sheet shows. */
@Serializable
data class IncidentDetail(val dispatch: Dispatch? = null)

/** A CHP call's log, newest first, and one story per unit. */
@Serializable
data class Dispatch(val log: List<DispatchLine> = emptyList(), val units: List<DispatchUnit> = emptyList())

@Serializable
data class DispatchLine(val time: String? = null, val text: String? = null, val plain: String? = null)

@Serializable
data class DispatchUnit(val unit: Int? = null, val steps: List<UnitStep> = emptyList(), val done: Boolean = false)

@Serializable
data class UnitStep(val status: String? = null, val time: String? = null)

/**
 * Where the camera centres to show an event above the event sheet.
 * Centring on the event itself puts it under the sheet's top edge, so
 * the centre moves south by 0.22 of the screen height: the event sits
 * in the upper part of the map. The same sum as the iPhone app, in dp,
 * with MapLibre's 512-unit world.
 */
object EventCamera {
    fun metersPerDp(lat: Double, zoom: Double): Double =
        40075016.0 * kotlin.math.cos(Math.toRadians(lat)) / (512.0 * Math.pow(2.0, zoom))

    fun centerLat(lat: Double, zoom: Double, screenHeightDp: Double): Double =
        lat - 0.22 * screenHeightDp * metersPerDp(lat, zoom) / 111_320.0
}

/** Where an alert's event is now, put together from the server and the map. */
object EventResolve {
    /** How far from the alert a marker of the same kind still counts as it. */
    const val NEAR_METERS = 300.0

    /**
     * The alert's marker among [markers]: the one whose id is the CHP
     * call in a `chp:` event id, else the nearest of the kind within
     * [NEAR_METERS]. A push with no kind takes the nearest of the four
     * alert kinds.
     */
    fun nearest(markers: List<RoadMarker>, alert: AlertTap): RoadMarker? {
        val kinds = alert.kind?.let { setOf(it) } ?: setOf("incident", "lane_closure", "chain_control", "wildfire")
        val ofKind = markers.filter { it.kind in kinds }
        val chp = alert.eventId?.takeIf { it.startsWith("chp:") }?.removePrefix("chp:")
        chp?.let { id -> ofKind.firstOrNull { it.id == id }?.let { return it } }
        val at = LatLon(alert.lat, alert.lon)
        return ofKind.map { it to AlertsEngine.meters(LatLon(it.lat, it.lon), at) }
            .filter { it.second < NEAR_METERS }.minByOrNull { it.second }?.first
    }

    /**
     * The marker and banner for an alert. [answer] is null when the
     * server could not be asked; the map then decides: a marker still
     * there is active, but says it could not be confirmed, and no marker
     * is unknown rather than a guess that it ended.
     *
     * A cleared or gone event never borrows a marker from the map: the
     * server leaves it out on purpose, so a new call at the same spot is
     * never passed off as the one in the alert.
     */
    fun resolve(alert: AlertTap, answer: EventStatusAnswer?, held: List<RoadMarker>, nowMs: Long): Pair<RoadMarker?, EventStatus> {
        if (answer == null) {
            val local = nearest(held, alert)
            return if (local != null) local to EventStatus(EventState.ACTIVE, checkedAt = nowMs, unconfirmed = true)
            else null to EventStatus(EventState.UNKNOWN, checkedAt = nowMs)
        }
        val checked = EventText.parseIso(answer.checked_at) ?: nowMs
        return when (answer.state) {
            "active", "changed" -> {
                val marker = answer.marker ?: nearest(held, alert)
                val changed = answer.state == "changed"
                marker to EventStatus(
                    if (changed) EventState.CHANGED else EventState.ACTIVE, checkedAt = checked,
                    newTitle = if (changed) answer.event?.title ?: marker?.displayTitle else null,
                )
            }
            "cleared" -> null to EventStatus(EventState.CLEARED, checkedAt = checked,
                clearedAt = EventText.parseIso(answer.cleared_at), nearby = answer.nearby)
            "gone" -> null to EventStatus(EventState.GONE, checkedAt = checked)
            else -> null to EventStatus(EventState.UNKNOWN, checkedAt = checked)
        }
    }
}

/** The banner's words. Copy is shared with the iPhone app; keep them identical. */
data class BannerText(val headline: String, val detail: String?, val retry: Boolean = false)

object EventBanner {
    fun text(status: EventStatus, alert: AlertTap?, markerKind: String?, nowMs: Long, zone: ZoneId, locale: Locale = Locale.US): BannerText {
        val sentMs = alert?.sentAt?.let { it * 1000 }
        val sentAgo = sentMs?.let { EventText.agoMs(it, nowMs) }
        val sentClock = sentMs?.let { EventText.clock(it, nowMs, zone, locale) }
        // The alert is shown under the banner only when nothing replaced it.
        val yourAlert = when {
            alert == null -> ""
            sentClock != null -> " Your alert from $sentClock is below."
            else -> " Your alert is below."
        }
        val noun = EventKinds.noun(markerKind ?: alert?.kind)
        return when (status.state) {
            EventState.LOADING -> BannerText("Checking the latest status", sentAgo?.let { "Alert sent $it." })
            EventState.ACTIVE -> BannerText("Still active",
                (if (status.unconfirmed) "Couldn't confirm it just now, but it is still on the map." else "Checked just now.") +
                    (sentAgo?.let { " Alert sent $it." } ?: ""))
            EventState.CHANGED -> BannerText("Changed since your alert",
                listOfNotNull(status.newTitle?.let { "Now: ${sentence(it)}" }, alert?.title?.let { "Your alert said: ${sentence(it)}" })
                    .joinToString(" ").ifEmpty { null })
            EventState.CLEARED -> BannerText(status.clearedAt?.let { "Cleared " + EventText.agoMs(it, nowMs) } ?: "Cleared",
                "This $noun is no longer reported.$yourAlert")
            EventState.GONE -> BannerText("No longer reported", "It ended or the agency stopped reporting it.$yourAlert")
            EventState.UNKNOWN -> BannerText("Couldn't check the status", "Showing what the alert said.", retry = true)
        }
    }

    /** A title quoted inside a sentence gets the sentence's full stop. */
    private fun sentence(s: String): String = s.trim().let { if (it.endsWith('.') || it.endsWith('!') || it.endsWith('?')) it else "$it." }
}

/**
 * The web map's wording helpers, ported from static/map-app.js
 * (agoTxt, humanize, shapeShout, splitRoad, chpGloss, whenPhrase,
 * spanPhrase, schedPanel, CHAIN_LEVELS, TZ_BY_SRC). The strings are the
 * website's, word for word: the three surfaces read the same.
 */
object EventText {
    /** An ISO time in epoch ms, or null. A time without an offset is UTC. */
    fun parseIso(iso: String?): Long? {
        if (iso.isNullOrBlank()) return null
        return runCatching { OffsetDateTime.parse(iso).toInstant().toEpochMilli() }.getOrNull()
            ?: runCatching { Instant.parse(iso).toEpochMilli() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(iso).toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrNull()
    }

    /** agoTxt: "just now", "12 min ago", "3 hours ago", "2 days ago". */
    fun ago(iso: String?, nowMs: Long): String? = parseIso(iso)?.let { agoMs(it, nowMs) }

    fun agoMs(thenMs: Long, nowMs: Long): String {
        val mins = jsRound((nowMs - thenMs) / 60000.0)
        if (mins < 1) return "just now"
        if (mins < 60) return "$mins min ago"
        if (mins < 48 * 60) {
            val h = jsRound(mins / 60.0)
            return "$h" + if (h == 1L) " hour ago" else " hours ago"
        }
        return "${jsRound(mins / 1440.0)} days ago"
    }

    /** A clock time, "9:41 AM", with the weekday when it is most of a day away. */
    fun clock(ms: Long, nowMs: Long, zone: ZoneId, locale: Locale = Locale.US): String {
        val t = Instant.ofEpochMilli(ms).atZone(zone)
        val pattern = if (abs(ms - nowMs) > 20 * 3600 * 1000L) "EEE " + UnitStyle.clockPattern else UnitStyle.clockPattern
        return t.format(DateTimeFormatter.ofPattern(pattern, locale))
    }

    /** JavaScript's Math.round: halves go up, also below zero. */
    private fun jsRound(v: Double): Long = Math.floor(v + 0.5).toLong()

    /** A number as JavaScript prints it: 15, not 15.0. */
    fun num(v: Double): String = if (v == Math.floor(v) && abs(v) < 1e15) v.toLong().toString() else v.toString()

    /** humanize: "LaneClosure" or "LANE_CLOSURE" becomes "Lane closure". */
    fun humanize(t: String?): String? {
        if (t.isNullOrEmpty()) return null
        var s = t.replace(Regex("([a-z])([A-Z])"), "$1 $2")
            .replace(Regex("[_-]+"), " ").replace(Regex("\\s+"), " ").trim()
        if (s.isEmpty()) return null
        s = if (s == s.uppercase()) s.lowercase() else s.substring(0, 1).lowercase() + s.substring(1)
        return s.substring(0, 1).uppercase() + s.substring(1)
    }

    private val ROAD = Regex("\\b(us|i|sr|nv|ca|az|ut|wa|or|id|co|nm|mt|wy|nd|sd)-?(\\d+[a-z]*)\\b")

    /**
     * shapeShout: an all-caps operator dump ("CLOSED DUE TO X//USE Y")
     * reads as shouting, so it is sentence-cased and its slash chains
     * become sentences. Route numbers stay in capitals.
     */
    fun shapeShout(t: String?): String? {
        if (t.isNullOrEmpty()) return t
        val letters = t.filter { it in 'A'..'Z' || it in 'a'..'z' }
        val caps = letters.count { it in 'A'..'Z' }
        if (letters.isEmpty() || caps.toDouble() / letters.length < 0.8) return t
        return t.split(Regex("\\s*/{1,2}\\s*")).filter { it.isNotEmpty() }.joinToString(" ") { raw ->
            var seg = raw.lowercase().trim()
            seg = ROAD.replace(seg) { m -> m.groupValues[1].uppercase() + "-" + m.groupValues[2].uppercase() }
            val cap = if (seg.isEmpty()) seg else seg.substring(0, 1).uppercase() + seg.substring(1)
            cap + if (Regex("[.!?]$").containsMatchIn(seg)) "" else "."
        }
    }

    /** splitRoad: "US 89: Emergency Maintenance, NB State St" into road and rest. */
    fun splitRoad(label: String?): Pair<String?, String?> {
        val m = Regex("^([A-Z]{1,3}[- ]?\\d+[A-Z]?(?:/[A-Z0-9-]+)?)\\s*[:-]\\s*(.+)$").find(label ?: "")
        return if (m != null) m.groupValues[1] to m.groupValues[2] else null to label
    }

    /** CHP dispatch codes, decoded for people who don't speak scanner. */
    private val CHP_CODES = listOf(
        Regex("^1125") to "A traffic hazard is on or near the road: debris, an animal, or a stalled vehicle. These usually clear quickly. Expect brief slowing.",
        Regex("^1179") to "Collision with injuries. An ambulance is on the way. Lanes can be blocked while crews work.",
        Regex("^1181") to "Collision with minor injuries reported. Expect brief lane blockage while crews clear the scene.",
        Regex("^1182") to "Collision, property damage only. No injuries are reported. Vehicles can be on the shoulder.",
        Regex("^1183") to "Collision reported, details still coming in. CHP has the call but no injury assessment yet.",
        Regex("^20001") to "Hit and run with injuries (felony). CHP is investigating. The scene can block lanes.",
        Regex("^20002") to "Hit and run, property damage only. Usually a short stop on the shoulder.",
        Regex("^23114") to "A load has spilled from a vehicle onto the road. Lanes can close briefly for cleanup.",
        Regex("^1166") to "A traffic signal is defective. Treat the intersection as an all-way stop.",
        Regex("SIG", RegexOption.IGNORE_CASE) to "A SIG Alert: a major incident expected to block lanes for 30 minutes or more. Avoid the area if you can.",
        Regex("fire", RegexOption.IGNORE_CASE) to "A fire reported on or near the road. Smoke can cut visibility. Expect crews and closures.",
        Regex("ped", RegexOption.IGNORE_CASE) to "A pedestrian is involved or on the road. Slow down and give the scene room.",
        Regex("animal", RegexOption.IGNORE_CASE) to "A live or struck animal on the road. Expect brief slowing.",
    )

    fun chpGloss(type: String?): String? = CHP_CODES.firstOrNull { it.first.containsMatchIn(type ?: "") }?.second

    /** California's chain control levels, in order. */
    val CHAIN_LEVELS = listOf(
        "R-1" to "Chains or approved snow tires required. Carry chains even with snow tires.",
        "R-2" to "Chains required on every vehicle, except 4WD/AWD with snow tires on all four wheels. Even those must carry chains.",
        "R-3" to "Chains required on every vehicle, no exceptions. Plan for a full closure.",
    )

    /** Each marker source's road timezone; states that span zones get the one covering most of their roads. */
    val TZ_BY_SRC = mapOf(
        "WSDOT" to "America/Los_Angeles",
        "Oregon DOT (TripCheck)" to "America/Los_Angeles",
        "NDOT" to "America/Los_Angeles",
        "511.org" to "America/Los_Angeles", "BATA" to "America/Los_Angeles",
        "GGB" to "America/Los_Angeles",
        "Alaska DOT&PF" to "America/Anchorage",
        "HDOT" to "Pacific/Honolulu",
        "ITD" to "America/Boise",
        "UDOT" to "America/Denver", "CDOT" to "America/Denver",
        "ADOT" to "America/Phoenix",
        "WisDOT" to "America/Chicago", "MnDOT" to "America/Chicago",
        "KDOT" to "America/Chicago", "MoDOT" to "America/Chicago",
        "ODOT (OK)" to "America/Chicago", "Louisiana DOTD" to "America/Chicago",
        "City of Austin" to "America/Chicago", "Iowa DOT" to "America/Chicago",
        "TravelMidwest (IDOT)" to "America/Chicago",
        "MDOT Traffic (MS)" to "America/Chicago",
        "TDOT SmartWay" to "America/Chicago",
        "ALGO Traffic (ALDOT)" to "America/Chicago",
        "NTTA" to "America/Chicago", "HCTRA" to "America/Chicago",
        "MDOT MiDrive" to "America/Detroit",
        "511NY" to "America/New_York", "NJDOT" to "America/New_York",
        "MDOT SHA" to "America/New_York", "MDOT CHART" to "America/New_York",
        "KYTC" to "America/New_York", "DelDOT" to "America/New_York",
        "FDOT" to "America/New_York", "FDOT (WZDx)" to "America/New_York",
        "NCDOT" to "America/New_York", "CTDOT" to "America/New_York",
        "MaineDOT" to "America/New_York", "NHDOT" to "America/New_York",
        "VTrans" to "America/New_York", "VDOT" to "America/New_York",
        "OHGO" to "America/New_York",
        "INDOT" to "America/Indiana/Indianapolis",
    )

    /** The road's timezone. No source means California. */
    fun roadZone(src: String?): ZoneId = ZoneId.of(TZ_BY_SRC[src] ?: "America/Los_Angeles")

    private fun zoneAbbr(t: Instant, zone: ZoneId): String =
        DateTimeFormatter.ofPattern("zzz", Locale.US).format(t.atZone(zone))

    /** The two zones show the same wall clock at [t]. */
    private fun sameClock(t: Instant, a: ZoneId, b: ZoneId): Boolean =
        a.rules.getOffset(t) == b.rules.getOffset(t)

    /**
     * whenPhrase: "tonight at 9:00 PM", "Thursday at 6:00 AM".
     * [zoneMode] 0 adds no zone, 1 the zone's abbreviation, 2 also
     * "(your timezone)" when it is the viewer's clock too.
     */
    fun whenPhrase(epoch: Long, zone: ZoneId, zoneMode: Int, nowMs: Long, viewer: ZoneId): String {
        val t = Instant.ofEpochSecond(epoch)
        val local = t.atZone(zone)
        val clock = local.format(DateTimeFormatter.ofPattern(UnitStyle.clockPattern, Locale.US))
        val dayGap = ChronoUnit.DAYS.between(Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate(), local.toLocalDate())
        val day = when (dayGap) {
            0L -> if (local.hour >= 18) "tonight" else "today"
            1L -> "tomorrow"
            -1L -> "yesterday"
            else -> local.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.US) +
                (if (abs(dayGap) > 6) ", " + local.format(DateTimeFormatter.ofPattern("MMM d", Locale.US)) else "") +
                (if (abs(dayGap) > 300) ", " + local.year else "")
        }
        var s = "$day at $clock"
        if (zoneMode > 0) {
            s += " " + zoneAbbr(t, zone)
            if (zoneMode == 2 && sameClock(t, zone, viewer)) s += " (your timezone)"
        }
        return s
    }

    /** spanPhrase: "40 minutes", "about 3 hours", "about 2 days". */
    fun spanPhrase(epoch: Long, nowMs: Long): String {
        val mins = jsRound(abs(nowMs / 1000.0 - epoch) / 60)
        if (mins < 60) return "$mins minutes"
        if (mins < 60 * 36) {
            val h = jsRound(mins / 60.0)
            return "about $h" + if (h == 1L) " hour" else " hours"
        }
        val d = jsRound(mins / 1440.0)
        return "about $d" + if (d == 1L) " day" else " days"
    }

    /**
     * schedPanel: when a closure is scheduled to end, never promoted to
     * an observation. [zoneLines] is the "In your timezone:" block, only
     * when the viewer's clock differs from the road's.
     */
    fun schedule(m: RoadMarker, nowMs: Long, viewer: ZoneId): Schedule {
        val now = nowMs / 1000.0
        val agency = m.src?.takeIf { it.isNotEmpty() } ?: "Caltrans"
        val tz = roadZone(m.src)
        val since = m.since?.takeIf { it != 0L }
        val until = m.until?.takeIf { it != 0L }
        val full = m.cls == "full-roadway"
        val started = since?.let { " It started " + whenPhrase(it, tz, 0, nowMs, viewer) + "." } ?: ""
        val (head, tail) = when {
            until != null && until < now -> ("Was scheduled to end " + whenPhrase(until, tz, 2, nowMs, viewer)) to
                ("That was " + spanPhrase(until, nowMs) + " ago. " +
                    if (full) "$agency has not reported it open. Assume the road is still closed."
                    else "$agency has not reported it clear. Assume the restriction is still there.")
            until != null -> ("Scheduled to end " + whenPhrase(until, tz, 2, nowMs, viewer)) to
                ("That is " + spanPhrase(until, nowMs) + " from now." + started)
            else -> "No scheduled end" to
                ((if (full) "The road stays closed until $agency reports it open."
                  else "The restriction stays until $agency reports it clear.") + started)
        }
        val rows = listOfNotNull(since?.let { "Start" to it }, until?.let { "Scheduled end" to it })
        val differs = rows.any { (_, ep) -> !sameClock(Instant.ofEpochSecond(ep), tz, viewer) }
        val zoneLines = if (rows.isEmpty() || !differs) emptyList() else
            listOf("In your timezone:") + rows.map { (label, ep) -> "$label: " + fullWhen(ep, viewer) }
        return Schedule(head, tail, zoneLines)
    }

    private fun fullWhen(epoch: Long, zone: ZoneId): String {
        val t = Instant.ofEpochSecond(epoch)
        return t.atZone(zone).format(DateTimeFormatter.ofPattern("EEEE, MMM d 'at' " + UnitStyle.clockPattern, Locale.US)) + " " + zoneAbbr(t, zone)
    }

    /**
     * A Caltrans chain control: the level that applies now gets the
     * bold panel, the others sit below as reference so the level has
     * meaning. A status that is not a level gets the whole legend.
     */
    fun chainPanel(status: String?): ChainPanel {
        val norm = chainLevel(status)
        val active = CHAIN_LEVELS.firstOrNull { it.first == norm }
        return if (active != null) ChainPanel("Caltrans reports $norm here", active.second, CHAIN_LEVELS.filter { it.first != norm })
        else ChainPanel(null, null, CHAIN_LEVELS)
    }

    /** "r2" and "R2" read as "R-2". */
    fun chainLevel(status: String?): String = (status ?: "").uppercase().replace(Regex("^R(\\d)$"), "R-$1")

    /** One unit's story: "Unit 1: assigned 12:39 AM, en route 12:40 AM". */
    fun unitLine(u: DispatchUnit, index: Int): String =
        "Unit ${u.unit ?: (index + 1)}: " + u.steps.joinToString(", ") { listOfNotNull(it.status, it.time).joinToString(" ") } +
            if (u.done) "" else ". Still working the scene"
}

data class Schedule(val head: String, val tail: String, val zoneLines: List<String>)

/** [head] and [text] are null when the status is not a level: then [legend] is all of them. */
data class ChainPanel(val head: String?, val text: String?, val legend: List<Pair<String, String>>)

/**
 * Everything the event sheet says about a marker, kind by kind, ported
 * from the web map's popupFor. Pictures, boards and prices stay in the
 * app's own views; this is the words.
 */
data class EventCard(
    val chip: String,
    /** A full closure takes a darker red than the closure dot. */
    val darker: Boolean = false,
    val age: String? = null,
    val title: String,
    val subtitle: String? = null,
    /** Closures: "All lanes closed", or the lanes text. */
    val warning: String? = null,
    val body: List<String> = emptyList(),
    val gloss: String? = null,
    val facts: List<Pair<String, String>> = emptyList(),
    val footer: List<String> = emptyList(),
    val schedule: Schedule? = null,
    val chain: ChainPanel? = null,
    /** Show the dispatch log button: an incident with log entries. */
    val dispatchCount: Int = 0,
    /** A plugin's own page for the alert. */
    val link: String? = null,
) {
    companion object {
        fun of(m: RoadMarker, nowMs: Long, viewer: ZoneId, miles: Boolean): EventCard = when (m.kind) {
            "incident" -> incident(m, nowMs)
            "lane_closure" -> closure(m, nowMs, viewer)
            "chain_control" -> chain(m, nowMs)
            "wildfire" -> fire(m, nowMs)
            "camera" -> EventCard(
                chip = "Camera", title = m.name?.takeIf { it.isNotBlank() } ?: "Roadside camera",
                subtitle = listOf(listOfNotNull(m.route, m.direction).filter { it.isNotBlank() }.joinToString(" "), m.near ?: "")
                    .filter { it.isNotBlank() }.joinToString(", ").ifEmpty { null },
                footer = listOf("Source: " + (m.src?.takeIf { it.isNotBlank() }?.let { "$it camera network" } ?: "Caltrans CCTV")),
            )
            "sign" -> EventCard(
                chip = "Message sign",
                title = listOfNotNull(m.route, m.direction).filter { it.isNotBlank() }.joinToString(" ").ifEmpty { "Changeable sign" },
                subtitle = m.near?.takeIf { it.isNotBlank() },
                footer = listOf("Source: " + (m.src?.takeIf { it.isNotBlank() }?.let { "$it message signs" } ?: "Caltrans CMS")),
            )
            "rwis" -> weather(m, miles)
            "toll" -> EventCard(
                chip = "Toll", title = m.corridor?.takeIf { it.isNotBlank() } ?: m.name?.takeIf { it.isNotBlank() } ?: "Toll",
                subtitle = m.toll_dir?.takeIf { it.isNotBlank() }?.let { d ->
                    listOfNotNull(EventText.humanize(d), m.toll_note?.takeIf { it.isNotBlank() }).joinToString(", ")
                },
                footer = listOfNotNull(when {
                    m.src == "511.org" -> "Toll data provided by 511.org"
                    m.src == "BATA" -> "Posted schedule, Bay Area Toll Authority"
                    m.src == "GGB" -> "Posted schedule, Golden Gate Bridge District"
                    !m.src.isNullOrBlank() -> "Prices provided by ${m.src}"
                    else -> null
                }),
            )
            "plugin" -> plugin(m, nowMs)
            else -> EventCard(chip = m.kind.replace('_', ' ').replaceFirstChar { it.uppercase() }, title = m.displayTitle)
        }

        /** The chip when there is no marker, only an alert of this kind. */
        fun chipFor(kind: String?): String = when (kind) {
            "incident" -> "Incident"
            "lane_closure" -> "Closure"
            "chain_control" -> "Chain control"
            "wildfire" -> "Wildfire"
            else -> "Alert"
        }

        private fun incident(m: RoadMarker, nowMs: Long): EventCard {
            val (road, rest) = EventText.splitRoad(m.label ?: "")
            val body = mutableListOf<String>()
            // Out-of-state feeds ship a clean detail sentence; the
            // templated label fills in only when there is nothing better.
            if (!m.detail.isNullOrEmpty() && m.detail != m.label) EventText.shapeShout(m.detail)?.let { body.add(it) }
            else if (!m.label.isNullOrEmpty() && m.label != m.location) body.add(rest?.takeIf { it.isNotEmpty() } ?: m.label)
            val ago = EventText.ago(m.reported, nowMs)
            return EventCard(
                chip = "Incident", age = ago,
                title = EventText.humanize(m.type) ?: "Incident",
                subtitle = m.location?.takeIf { it.isNotEmpty() } ?: road,
                body = body, gloss = EventText.chpGloss(m.type),
                facts = listOfNotNull(
                    if (road != null && m.location.isNullOrEmpty()) "Road" to road else null,
                    m.dir?.takeIf { it.isNotEmpty() }?.let { "Direction" to "Affects the $it side" },
                    m.lanes?.takeIf { it.isNotEmpty() }?.let { "Lanes" to it },
                ),
                footer = listOf(
                    ago?.let { "Reported $it" } ?: "Live report",
                    "Source: " + (m.src?.takeIf { it.isNotEmpty() }?.let { "$it data feed" }
                        ?: ("CHP " + (m.area?.takeIf { it.isNotEmpty() }?.let { "$it " } ?: "") + "dispatch")),
                ),
                dispatchCount = if (!m.id.isNullOrEmpty()) (m.log_n ?: 0.0).toInt() else 0,
            )
        }

        /** The web map's closure groups: full, ramp, one-way and rolling work, and lanes. */
        fun closureChip(cls: String?): String = when {
            cls == "full-roadway" -> "Road closed"
            cls == "ramp" -> "Ramp closed"
            Regex("one-way|alternating|moving|traffic-break").containsMatchIn(cls ?: "") -> "One-way traffic"
            else -> "Lanes closed"
        }

        private fun closure(m: RoadMarker, nowMs: Long, viewer: ZoneId): EventCard {
            val full = m.cls == "full-roadway"
            val allLanes = full || Regex("all lanes", RegexOption.IGNORE_CASE).containsMatchIn(m.lanes ?: "")
            val prose = EventText.shapeShout(m.detail?.takeIf { it.isNotEmpty() } ?: m.label)
            return EventCard(
                chip = closureChip(m.cls), darker = full,
                title = listOfNotNull(m.route, m.county).filter { it.isNotEmpty() }.joinToString(", ").ifEmpty { "Closure" },
                subtitle = m.dir?.takeIf { it.isNotEmpty() },
                warning = if (allLanes) "All lanes closed" else m.lanes?.takeIf { it.isNotEmpty() },
                body = listOfNotNull(prose?.takeIf { it.isNotEmpty() }),
                facts = listOfNotNull(
                    m.work?.takeIf { it.isNotEmpty() }?.let { "Work" to (EventText.humanize(it) ?: it) },
                    m.delay_min?.takeIf { it != 0.0 }?.let { "Delay" to "~${EventText.num(it)} min expected" },
                    m.facility?.takeIf { it.isNotEmpty() && m.cls == "ramp" }?.let { "Facility" to it },
                    m.windows?.takeIf { it != 0.0 }?.let { "Windows" to "${EventText.num(it - 1)} more scheduled at this spot" },
                ),
                footer = listOf("Source: " + (m.src?.takeIf { it.isNotEmpty() }?.let { "$it data feed" } ?: "Caltrans lane closure system")),
                schedule = EventText.schedule(m, nowMs, viewer),
            )
        }

        private fun chain(m: RoadMarker, nowMs: Long): EventCard {
            val ago = EventText.ago(m.updated, nowMs)
            // The R system is California's. Other agencies publish free
            // text restrictions: shown as they wrote them, no legend.
            if (!m.src.isNullOrEmpty()) {
                val parts = (m.label ?: "").split(Regex(";\\s*")).map { it.trim() }.filter { it.isNotEmpty() }.distinct()
                val noInfo = Regex("no current information", RegexOption.IGNORE_CASE).containsMatchIn(m.label ?: "")
                return EventCard(
                    chip = "Pass restriction", age = ago,
                    title = m.route?.takeIf { it.isNotEmpty() } ?: m.status?.takeIf { it.isNotEmpty() } ?: "Mountain pass",
                    body = if (!noInfo && parts.isNotEmpty())
                        listOf(parts.joinToString(". ") + if (Regex("[.!?]$").containsMatchIn(parts.last())) "" else ".") else emptyList(),
                    gloss = if (noInfo) "${m.src} has not posted current restrictions for this pass." else null,
                    footer = listOf("Source: ${m.src} mountain pass reports"),
                )
            }
            val norm = EventText.chainLevel(m.status)
            return EventCard(
                chip = "Chain control", age = ago,
                title = (norm.ifEmpty { null } ?: m.status?.takeIf { it.isNotEmpty() } ?: "Chain control") +
                    (m.route?.takeIf { it.isNotEmpty() }?.let { " on $it" } ?: ""),
                subtitle = m.label?.takeIf { it.isNotEmpty() },
                footer = listOfNotNull(ago?.let { "Status set $it" }, "Source: Caltrans chain control feed"),
                chain = EventText.chainPanel(m.status),
            )
        }

        private fun fire(m: RoadMarker, nowMs: Long): EventCard {
            val ago = EventText.ago(m.discovered, nowMs)
            return EventCard(
                chip = "Wildfire", age = ago,
                title = (m.name?.takeIf { it.isNotEmpty() } ?: "Wildfire") + " Fire",
                // The dot is where it was reported; the outline is where
                // it is. Saying which is on screen is the difference
                // between a fire near a road and one on it.
                gloss = if (m.perimeter.isNotEmpty()) "The outline is the mapped burn footprint."
                        else "No mapped perimeter yet. The dot marks the reported origin.",
                facts = listOfNotNull(
                    m.acres?.takeIf { it != 0.0 }?.let { "Size" to "%,d acres".format(Locale.US, Math.round(it)) },
                    m.contained?.let { "Contained" to "${EventText.num(it)}% contained" },
                    ago?.let { "Discovered" to it },
                ),
                footer = listOf("Source: WFIGS national fire data, with CAL FIRE perimeters"),
            )
        }

        /** Station readings, in the driver's units: the station reports Celsius, mph and metres. */
        private fun weather(m: RoadMarker, miles: Boolean): EventCard {
            fun temperature(c: Double) = if (UnitStyle.fahrenheit ?: miles) "${Math.round(c * 9 / 5 + 32)} F" else "${Math.round(c)} C"
            fun speed(mph: Double) = if (miles) "${Math.round(mph)} mph" else "${Math.round(mph * 1.609344)} km/h"
            // A direction on calm wind ("0 mph from the E") is noise.
            val from = m.windFrom?.takeIf { m.wind == null || Math.round(m.wind) >= 1 }?.let { " from the $it" } ?: ""
            val facts = listOfNotNull(
                m.air_c?.let { "Air" to temperature(it) },
                m.pave_c?.let { "Pavement" to temperature(it) },
                when {
                    m.wind != null -> "Wind" to speed(m.wind) + from + (m.gust?.let { ", gusts ${speed(it)}" } ?: "")
                    m.gust != null -> "Wind" to "gusts ${speed(m.gust)}$from"
                    else -> null
                },
                m.rh?.let { "Humidity" to "${Math.round(it)}%" },
                m.precip?.takeIf { it.isNotEmpty() }?.let { "Precip" to (EventText.humanize(it) ?: it) },
                m.surface?.takeIf { it.isNotEmpty() }?.let { "Surface" to it },
                m.vis_m?.takeIf { it < 5000 }?.let { "Visibility" to Units.distance(it, miles) },
            )
            return EventCard(
                chip = "Road weather", title = m.station?.takeIf { it.isNotEmpty() } ?: m.name?.takeIf { it.isNotEmpty() } ?: "Weather station",
                subtitle = m.route?.takeIf { it.isNotEmpty() },
                gloss = if (facts.isEmpty()) "This station is online. It has no readings right now." else null,
                facts = facts,
                footer = listOf("Source: " + (m.src?.takeIf { it.isNotEmpty() }?.let { "$it weather station" } ?: "Caltrans roadside weather station")),
            )
        }

        private fun plugin(m: RoadMarker, nowMs: Long): EventCard {
            // A camera reads the way people say it ("Speed camera"), and
            // its description opens with the same words, so they come
            // off the line under the title.
            val camera = mapOf("CAMERA_SPEED" to "Speed camera", "CAMERA_RED_LIGHT" to "Red light camera")[m.flare_kind]
            val kind = camera ?: EventText.humanize((m.flare_kind ?: "OTHER").lowercase().replace('_', ' ')) ?: "Other"
            var about = m.label ?: ""
            if (camera != null && about.lowercase().startsWith(camera.lowercase())) {
                about = about.substring(camera.length).replace(Regex("^[,.\\s]+"), "")
                about = about.replaceFirstChar { it.uppercase() }
            }
            // Something fixed in place was not "reported 38 minutes ago".
            val fixed = (m.ttl_s ?: 0.0) >= 86400
            val n = (m.confirmations ?: 0.0).toInt()
            return EventCard(
                chip = m.source?.takeIf { it.isNotEmpty() } ?: "Plugin",
                age = if (fixed) null else EventText.ago(m.reported, nowMs),
                title = kind, subtitle = about.ifEmpty { null },
                facts = listOfNotNull(
                    m.road?.takeIf { it.isNotEmpty() }?.let { "Road" to it },
                    if (n != 0) "Confirmed" to "$n" + (if (n == 1) " time" else " times") else null,
                    if (m.reliability != null && !fixed) "Reliability" to "${Math.round(m.reliability * 100)}%" else null,
                    m.data?.takeIf { it.isNotEmpty() }?.let { "Data from" to it },
                ),
                footer = listOf("Source: " + (m.source?.takeIf { it.isNotEmpty() } ?: "community plugin") + when {
                    m.tier == "approved" -> " (approved by CommuteScout)"
                    m.tier == "unreviewed" -> " (public, not reviewed)"
                    !m.trust.isNullOrEmpty() -> " (${m.trust})"
                    else -> ""
                }),
                link = m.source_url?.takeIf { it.startsWith("https://") },
            )
        }
    }
}
