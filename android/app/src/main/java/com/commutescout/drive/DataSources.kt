package com.commutescout.drive

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.Request
import java.time.Instant
import java.time.OffsetDateTime

/** A feed's health, as /api/sources reports it. */
enum class FeedStatus(val word: String) {
    FRESH("Fresh"), STALE("Stale"), DOWN("Down"), LIVE("Live"), OFF("Off");

    companion object {
        fun of(s: String?): FeedStatus? = entries.firstOrNull { it.name.equals(s, ignoreCase = true) }
    }
}

/** One feed from /api/sources, with the health fields worked out when the server is older and leaves them out. */
data class Feed(
    val name: String,
    val agency: String,
    val state: String,
    val status: FeedStatus,
    val ageS: Long?,
    val national: Boolean,
    val stateCode: String?,
    val asOfMs: Long?,
)

/** A row on the Data sources page: a national feed, or every feed of one state. */
data class FeedRow(val code: String, val title: String, val by: String, val status: FeedStatus, val ageS: Long?, val asOfMs: Long?)

data class SourcesReport(
    val checkedAtMs: Long?,
    val fresh: Int,
    val stale: Int,
    val down: Int,
    val states: Int,
    val national: List<FeedRow>,
    val stateRows: List<FeedRow>,
) {
    /** The Settings home row: "1 down", "2 stale" or "All fresh". */
    val headline: String get() = when {
        down > 0 -> "$down down"
        stale > 0 -> "$stale stale"
        else -> "All fresh"
    }
    val worst: FeedStatus get() = if (down > 0) FeedStatus.DOWN else if (stale > 0) FeedStatus.STALE else FeedStatus.FRESH
    /** "All 50 states and DC" when every state answers, else the count. */
    val coverage: String get() = if (states >= 51) "All 50 states and DC" else if (states == 1) "1 state" else "$states states"
}

/** Reads /api/sources. Pure, for tests: [parse] takes the body. */
object SourcesHealth {
    /** The server's own limit for a feed with no stale_after_s, in seconds. */
    private const val DEFAULT_STALE_S = 90 * 60L

    private val CODES = mapOf(
        "Alabama" to "AL", "Alaska" to "AK", "Arizona" to "AZ", "Arkansas" to "AR", "California" to "CA", "Colorado" to "CO",
        "Connecticut" to "CT", "Delaware" to "DE", "District of Columbia" to "DC", "Florida" to "FL", "Georgia" to "GA",
        "Hawaii" to "HI", "Idaho" to "ID", "Illinois" to "IL", "Indiana" to "IN", "Iowa" to "IA", "Kansas" to "KS",
        "Kentucky" to "KY", "Louisiana" to "LA", "Maine" to "ME", "Maryland" to "MD", "Massachusetts" to "MA",
        "Michigan" to "MI", "Minnesota" to "MN", "Mississippi" to "MS", "Missouri" to "MO", "Montana" to "MT",
        "Nebraska" to "NE", "Nevada" to "NV", "New Hampshire" to "NH", "New Jersey" to "NJ", "New Mexico" to "NM",
        "New York" to "NY", "North Carolina" to "NC", "North Dakota" to "ND", "Ohio" to "OH", "Oklahoma" to "OK",
        "Oregon" to "OR", "Pennsylvania" to "PA", "Rhode Island" to "RI", "South Carolina" to "SC", "South Dakota" to "SD",
        "Tennessee" to "TN", "Texas" to "TX", "Utah" to "UT", "Vermont" to "VT", "Virginia" to "VA", "Washington" to "WA",
        "West Virginia" to "WV", "Wisconsin" to "WI", "Wyoming" to "WY",
    )

    private fun JsonObject.str(k: String) = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.bool(k: String) = (this[k] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.long(k: String) = (this[k] as? JsonPrimitive)?.longOrNull
    private fun iso(s: String?): Long? = s?.let { runCatching { OffsetDateTime.parse(it).toInstant().toEpochMilli() }.getOrNull()
        ?: runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }

    /** One entry; the server's status when it sends one, else the same rules the server uses. */
    fun feed(o: JsonObject, nowMs: Long): Feed {
        val state = o.str("state") ?: ""
        val asOf = iso(o.str("as_of"))
        val age = o.long("age_s") ?: asOf?.let { ((nowMs - it) / 1000).coerceAtLeast(0) }
        val status = FeedStatus.of(o.str("status")) ?: when {
            o.bool("enabled") == false -> FeedStatus.OFF
            "ok" !in o -> FeedStatus.LIVE
            o.bool("ok") != true -> FeedStatus.DOWN
            o.bool("stale") == true || (age != null && age > (o.long("stale_after_s") ?: DEFAULT_STALE_S)) -> FeedStatus.STALE
            else -> FeedStatus.FRESH
        }
        val group = o.str("group")
        return Feed(o.str("name") ?: "Feed", o.str("agency") ?: "", state, status, age,
            national = group?.let { it == "national" } ?: (state == "Nationwide"),
            stateCode = o.str("state_code") ?: CODES[state], asOfMs = asOf)
    }

    fun parse(body: String, nowMs: Long): SourcesReport? {
        val root = runCatching { Backend.json.parseToJsonElement(body) }.getOrNull() as? JsonObject ?: return null
        val list = (root["sources"] as? JsonArray)?.mapNotNull { it as? JsonObject }?.map { feed(it, nowMs) } ?: return null
        return report(list, iso((root["checked_at"] as? JsonPrimitive)?.content), root["summary"] as? JsonObject)
    }

    fun report(feeds: List<Feed>, checkedAtMs: Long?, summary: JsonObject? = null): SourcesReport {
        fun count(k: String, s: FeedStatus) = (summary?.get(k) as? JsonPrimitive)?.intOrNull ?: feeds.count { it.status == s }
        // On-demand feeds are asked as needed, so they are as fresh as a feed can be.
        val fresh = count("fresh", FeedStatus.FRESH) + count("live", FeedStatus.LIVE)
        val states = (summary?.get("states") as? JsonPrimitive)?.intOrNull
            ?: feeds.filter { !it.national && it.stateCode != null && it.status != FeedStatus.OFF }.map { it.stateCode }.toSet().size
        val national = feeds.filter { it.national && it.status != FeedStatus.OFF }.map {
            FeedRow("US", it.name, it.agency, it.status, it.ageS, it.asOfMs)
        }
        val stateRows = feeds.filter { !it.national && it.status != FeedStatus.OFF && it.stateCode != null }
            .groupBy { it.stateCode!! }.map { (code, fs) ->
                // A state reads as its worst feed; its age is the oldest of the feeds that answer.
                val worst = fs.maxBy { rank(it.status) }
                val by = fs.map { it.agency }.filter { it.isNotEmpty() }.distinct().take(2).joinToString(", ")
                FeedRow(code, fs.first().state, by, worst.status, if (worst.status == FeedStatus.DOWN) worst.ageS else fs.mapNotNull { it.ageS }.maxOrNull(), worst.asOfMs)
            }.sortedBy { it.title }
        return SourcesReport(checkedAtMs, fresh, count("stale", FeedStatus.STALE), count("down", FeedStatus.DOWN), states, national, stateRows)
    }

    private fun rank(s: FeedStatus) = when (s) { FeedStatus.DOWN -> 3; FeedStatus.STALE -> 2; FeedStatus.FRESH -> 1; else -> 0 }

    /** "30 s ago", "22 min ago", "Live"; a down feed says when it last answered. */
    fun ageText(row: FeedRow, clock: (Long) -> String = { Units.clock(it) }): String = when {
        row.status == FeedStatus.LIVE -> "Live"
        row.status == FeedStatus.DOWN -> row.asOfMs?.let { "No reply since ${clock(it)}" } ?: "Not answering"
        row.ageS == null -> ""
        row.ageS < 60 -> "${row.ageS} s ago"
        row.ageS < 3600 -> "${row.ageS / 60} min ago"
        row.ageS < 48 * 3600 -> "${row.ageS / 3600} h ago"
        else -> "${row.ageS / 86400} days ago"
    }
}

/** The app's copy of /api/sources, fetched when Settings opens and on Refresh. */
object DataSources {
    private val _report = MutableStateFlow<SourcesReport?>(null)
    val report = _report.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy = _busy.asStateFlow()
    private val _failed = MutableStateFlow(false)
    val failed = _failed.asStateFlow()

    suspend fun refresh() {
        if (_busy.value) return
        _busy.value = true
        try {
            val body = withContext(Dispatchers.IO) {
                Backend.http.newCall(Request.Builder().url("${Backend.BASE}/api/sources").header("Accept", "application/json").build())
                    .execute().use { if (it.isSuccessful) it.body.string() else null }
            }
            val r = body?.let { SourcesHealth.parse(it, System.currentTimeMillis()) }
            if (r != null) { _report.value = r; _failed.value = false } else _failed.value = true
        } catch (e: Exception) {
            _failed.value = true
        } finally {
            _busy.value = false
        }
    }
}

