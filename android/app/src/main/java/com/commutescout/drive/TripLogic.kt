package com.commutescout.drive

import kotlinx.serialization.Serializable
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/*
 * The trip pages' logic, kept free of Compose so it can be tested:
 * search prefix bolding, what is on the way along a route, leave
 * later, the report steps and the arrive summary.
 */

object TripText {
    /** The place sheet with no drive time to show: on its way, not to be had, or no place to start from. */
    fun driveStatus(asked: Boolean, located: Boolean): String = when {
        asked -> "Drive time is not available right now"
        located -> "Checking the drive"
        else -> "Waiting for your location"
    }

    /** How many leading characters of [name] the query [q] matches, to set in bold; 0 when it does not start the name. */
    fun boldPrefix(name: String, q: String): Int {
        val t = q.trim()
        return if (t.isNotEmpty() && name.lowercase().startsWith(t.lowercase())) t.length else 0
    }

    /** "southbound" for a heading in degrees, or null without one. */
    fun bound(heading: Double?): String? {
        if (heading == null || heading < 0 || heading.isNaN()) return null
        return listOf("northbound", "eastbound", "southbound", "westbound")[(((heading % 360) + 45) / 90).toInt() % 4]
    }

    /** "3 routes", "1 route", or "Routes" before they are known. */
    fun routesLabel(n: Int?): String = when (n) { null, 0 -> "Routes"; 1 -> "1 route"; else -> "$n routes" }

    /** The short name an event goes by on the trip pages: "Crash", "2 lanes closed". */
    fun eventNoun(m: RoadMarker): String {
        val look = com.commutescout.drive.design.Looks.of(m)
        return when {
            m.kind == "lane_closure" -> m.laneLayout?.let { l ->
                val n = l.closedLanes.size
                if (n >= l.total) "Road closed" else if (n == 1) "1 lane closed" else "$n lanes closed"
            } ?: "Lane closure"
            m.kind == "chain_control" -> "Chain control"
            m.kind == "wildfire" -> "Wildfire"
            m.kind == "toll" -> "Toll lanes"
            m.kind == "rwis" -> "Icy pavement"
            look.icon == "crash" -> "Crash"
            look.icon == "closure" -> "Road closed"
            look.icon == "traffic" -> "Slow traffic"
            look.icon == "police" -> "Police"
            look.icon == "fire" -> "Fire"
            else -> "Hazard"
        }
    }

    /** "Crash on US-101 S", or just the noun when the road is unknown. */
    fun eventTitle(m: RoadMarker): String = eventNoun(m) + (m.route?.takeIf { it.isNotBlank() }?.let { " on $it" } ?: "")
}

/** Events on a route, in order along it. */
object OnTheWay {
    /** Kinds worth a row on the place card: what can slow or stop a drive. */
    val KINDS = setOf("incident", "lane_closure", "chain_control", "wildfire", "plugin", "toll", "rwis")

    /**
     * The markers within [maxOffset] metres of the line [pts] (wildfires
     * within 1.5 km), ahead of its start, not pointed the other way,
     * nearest first. Icy-road stations count only when icy.
     */
    fun along(pts: List<LatLon>, markers: List<RoadMarker>, maxOffset: Double = 60.0): List<Upcoming> {
        if (pts.size < 2) return emptyList()
        val cum = AlertsEngine.cumulativeDistances(pts)
        return markers.asSequence()
            .filter { it.kind in KINDS }
            .filter { it.kind != "rwis" || com.commutescout.drive.design.Looks.of(it).tone == com.commutescout.drive.design.Tone.MID }
            .mapNotNull { m ->
                val hit = AlertsEngine.along(pts, cum, LatLon(m.lat, m.lon))
                val limit = if (m.kind == "wildfire") 1500.0 else maxOffset
                if (hit.offset > limit) return@mapNotNull null
                val heading = AlertsEngine.headingOf(m)
                val seg = hit.segment.coerceIn(0, pts.size - 2)
                if (heading != null && AlertsEngine.angleBetween(heading, AlertsEngine.bearing(pts[seg], pts[seg + 1])) > 100) return@mapNotNull null
                Upcoming(m, hit.along)
            }
            .distinctBy { it.id }
            .sortedBy { it.alongMeters }
            .toList()
    }
}

@Serializable
data class LeaveDeparture(val depart_at: String? = null, val now: Boolean = false, val drive_min: Int? = null, val delay_min: Int? = null)

@Serializable
data class LeaveBest(val depart_at: String? = null, val drive_min: Int? = null, val saving_min: Int? = null)

/** /api/leave-later: drive time by departure for the next hour. */
@Serializable
data class LeaveLaterAnswer(
    val checked_at: String? = null,
    val departures: List<LeaveDeparture> = emptyList(),
    val best: LeaveBest? = null,
    val reason: String? = null,
)

object LeaveLater {
    data class Bar(val label: String, val minutes: Int, val height: Float, val now: Boolean, val best: Boolean)

    /** Worth a row: leaving now and at least one later time are known. */
    fun usable(a: LeaveLaterAnswer?): Boolean {
        if (a == null) return false
        val known = a.departures.filter { it.drive_min != null && it.depart_at != null }
        return known.size >= 2 && a.departures.firstOrNull()?.let { it.now && it.drive_min != null } == true
    }

    /**
     * One bar per known departure. Heights run from 0.25 (quickest) to 1
     * (slowest) of the bar room; all equal sit at 0.6. The best departure
     * is the server's pick, matched by its time.
     */
    fun bars(a: LeaveLaterAnswer, zone: ZoneId = ZoneId.systemDefault(), h24: Boolean = false): List<Bar> {
        val known = a.departures.filter { it.drive_min != null && it.depart_at != null }
        if (known.isEmpty()) return emptyList()
        val lo = known.minOf { it.drive_min!! }; val hi = known.maxOf { it.drive_min!! }
        return known.map { d ->
            val m = d.drive_min!!
            val f = if (hi == lo) .6f else .25f + .75f * (m - lo) / (hi - lo).toFloat()
            Bar(if (d.now) "Now" else clock(d.depart_at!!, zone, h24) ?: "", m, f, d.now, a.best?.depart_at != null && a.best.depart_at == d.depart_at)
        }
    }

    /** "Leave at 9:10 to save 8 min", or "Leave now" when no later time saves enough. */
    fun title(a: LeaveLaterAnswer, zone: ZoneId = ZoneId.systemDefault(), h24: Boolean = false): String {
        val b = a.best
        val at = b?.depart_at?.let { clock(it, zone, h24) }
        return if (b != null && at != null && (b.saving_min ?: 0) > 0) "Leave at $at to save ${b.saving_min} min" else "Leave now"
    }

    /** "9:10" in the phone's zone, from the server's ISO time. */
    fun clock(iso: String, zone: ZoneId = ZoneId.systemDefault(), h24: Boolean = false): String? = runCatching {
        OffsetDateTime.parse(iso).atZoneSameInstant(zone).format(DateTimeFormatter.ofPattern(if (h24) "H:mm" else "h:mm"))
    }.getOrNull()
}

/** The report sheet's steps: pick a kind, a five second undo window, then it sends. */
object ReportSteps {
    const val UNDO_MS = 5_000L

    sealed interface Step {
        data object Grid : Step
        data class Confirm(val kind: String) : Step
        data class Sending(val kind: String) : Step
        data class Sent(val kind: String) : Step
        data class Failed(val kind: String, val message: String) : Step
    }

    fun pick(kind: String): Step = Step.Confirm(kind)
    fun undo(s: Step): Step = if (s is Step.Confirm || s is Step.Failed) Step.Grid else s
    /** "Send now", or the undo window running out. Only a confirm step sends, and only once. */
    fun send(s: Step): Step = when (s) { is Step.Confirm -> Step.Sending(s.kind); is Step.Failed -> Step.Sending(s.kind); else -> s }
    fun sent(s: Step): Step = if (s is Step.Sending) Step.Sent(s.kind) else s
    fun failed(s: Step, message: String): Step = if (s is Step.Sending) Step.Failed(s.kind, message) else s

    /** Whole seconds left in the window when [progress] (0 to 1) of it has run. */
    fun secondsLeft(progress: Float): Int = kotlin.math.ceil((1f - progress.coerceIn(0f, 1f)) * UNDO_MS / 1000f).toInt()
}

/** A trip as the arrive sheet sums it up. */
data class TripRecord(
    val place: Place,
    val startedAt: Long,
    val meters: Double,
    /** Events the driver was alerted to ahead of reaching them, in order. */
    val warned: List<RoadMarker> = emptyList(),
    val arrivedAt: Long? = null,
)

object ArriveStats {
    data class Stats(val driveTime: String, val distance: String, val arrived: String)

    fun of(r: TripRecord, now: Long, miles: Boolean, clock: (Long) -> String): Stats {
        val end = r.arrivedAt ?: now
        val secs = ((end - r.startedAt) / 1000.0).coerceAtLeast(60.0)
        return Stats(Units.duration(secs), Units.distance(r.meters, miles), clock(end))
    }

    /** What the arrive sheet lists under "What you avoided": events that slow or stop a drive. */
    fun avoided(r: TripRecord): List<RoadMarker> =
        r.warned.filter { it.kind in AlertsEngine.CLEARABLE || it.kind == "wildfire" }.distinctBy { it.key }.take(3)
}

/** Minutes, rounded, for a route's seconds. */
fun routeMinutes(seconds: Double): Int = (seconds / 60).roundToInt()

/** What a driver can report, as the design's grid shows it. [flare] is the Flare kind sent. */
object ReportKinds {
    data class Kind(
        val id: String, val label: String, val icon: String, val tone: com.commutescout.drive.design.Tone, val flare: String,
        /** It sits in a lane: the confirm step asks which. */
        val lanes: Boolean = false,
        /** It sits beside the road: the confirm step asks, shoulder first. */
        val side: Boolean = false,
    ) {
        val asksWhere: Boolean get() = lanes || side
    }

    private val H = com.commutescout.drive.design.Tone.HIGH
    private val M = com.commutescout.drive.design.Tone.MID
    private val L = com.commutescout.drive.design.Tone.LOW
    val all = listOf(
        Kind("crash", "Crash", "crash", H, "CRASH_MAJOR", lanes = true),
        Kind("jam", "Slowdown", "traffic", M, "JAM_HEAVY"),
        Kind("police", "Police", "police", L, "POLICE_VISIBLE", side = true),
        Kind("hazard", "Object on road", "hazard", M, "HAZARD_OBJECT", lanes = true),
        Kind("shoulder", "Car on shoulder", "carside", M, "HAZARD_SHOULDER_CAR", side = true),
        Kind("closure", "Road closed", "closure", H, "ROAD_CLOSED"),
        Kind("lane", "Lane closed", "lane", H, "LANE_CLOSED", lanes = true),
        Kind("ice", "Ice or snow", "ice", M, "WEATHER_ICE"),
        Kind("fog", "Fog", "fog", M, "WEATHER_FOG"),
        Kind("flood", "Flooding", "flood", H, "WEATHER_FLOOD"),
        Kind("chain", "Chains required", "chain", H, "CHAINS_REQUIRED"),
        Kind("map", "Map issue", "mapi", L, "MAP_ISSUE"),
    )

    fun byFlare(flare: String): Kind? = all.firstOrNull { it.flare == flare }

    /** Where on the road: the confirm step's choices. */
    val WHERE = listOf("Left lane", "Right lane", "Shoulder")

    /** The choice a kind starts on: the shoulder for things beside the road, else the right lane. */
    fun defaultWhere(k: Kind): Int = if (k.side) 2 else 1

    /** The description sent: where on the road, then the driver's note. */
    fun description(k: Kind, where: Int?, note: String): String {
        val place = if (k.asksWhere && where != null) WHERE.getOrNull(where)?.let { "$it." } else null
        return listOfNotNull(place, note.trim().ifEmpty { null }).joinToString(" ")
    }

    /** "Report a crash here, southbound". */
    fun confirmTitle(k: Kind, bound: String?): String {
        val noun = when (k.id) {
            "crash" -> "a crash"; "jam" -> "a slowdown"; "police" -> "police"; "hazard" -> "an object on the road"
            "shoulder" -> "a car on the shoulder"; "closure" -> "a road closure"; "lane" -> "a lane closure"
            "ice" -> "ice or snow"; "fog" -> "fog"; "flood" -> "flooding"; "chain" -> "chains required"; else -> "a map issue"
        }
        return "Report $noun here" + (bound?.let { ", $it" } ?: "")
    }
}
