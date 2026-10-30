package com.commutescout.drive

/**
 * The marketplace and plugin page's rules and words, apart from the UI
 * so they can be unit tested: what counts as official data, the filter,
 * the count line and every line on the plugin page that depends on data.
 */
object Market {
    /** Where a plugin's data comes from. */
    enum class Data { OFFICIAL, PLUGIN }

    enum class Filter(val label: String) { ALL("All"), OFFICIAL("Official data"), PLUGIN("Plugin data") }

    /** Official data is what CommuteScout runs itself from public sources
     *  (the catalog's trust "official"). Everything else, reviewed or not,
     *  is plugin data: it comes from the plugin's maker. */
    fun data(s: FlareSource): Data = if (s.trust == "official") Data.OFFICIAL else Data.PLUGIN

    fun filter(list: List<FlareSource>, f: Filter): List<FlareSource> = when (f) {
        Filter.ALL -> list
        Filter.OFFICIAL -> list.filter { data(it) == Data.OFFICIAL }
        Filter.PLUGIN -> list.filter { data(it) == Data.PLUGIN }
    }

    /** In the person's list: shown on the map, or switched off for now. */
    fun isAdded(id: String, hidden: Set<String>, paused: Set<String>) = id !in hidden || id in paused

    /** "2 added, 4 more to try", "All 3 added" or "4 to try". */
    fun countLine(visible: Int, added: Int): String = when {
        visible == 0 -> "Nothing listed here yet"
        added >= visible -> "All $visible added"
        added > 0 -> "$added added, ${visible - added} more to try"
        else -> "$visible to try"
    }

    /** Who makes it, under its name. A maker named the same as the plugin says nothing twice. */
    fun maker(s: FlareSource): String = when {
        s.trust == "official" -> "By CommuteScout"
        s.tier == "private" -> "Added by you"
        else -> s.attribution?.takeIf { it.isNotBlank() && it != s.name }?.let { "By $it" } ?: "By its community"
    }

    /** What it does, in one or two lines. */
    fun purpose(s: FlareSource): String =
        s.summary?.takeIf { it.isNotBlank() } ?: if (s.kindsLabel.isEmpty()) "Alerts for your map." else "Shows ${s.kindsLabel} on your map."

    /** The design icon on its badge, from what it shows. */
    fun glyph(kinds: List<String>): String = when {
        kinds.isEmpty() -> "piece"
        kinds.all { it.startsWith("CAMERA") } -> "camera"
        kinds.any { it.startsWith("POLICE") || it.startsWith("CRASH") || it.startsWith("HAZARD") || it.startsWith("JAM") } -> "people"
        kinds.all { it.startsWith("WEATHER") } -> "fog"
        kinds.all { it.startsWith("CHAINS") } -> "chain"
        else -> "piece"
    }

    fun showSub(on: Boolean) = if (on) "Its alerts are on your map" else "Off for now. Nothing is shown or asked for."

    /** The "In alerts" line: no plugin speaks unless the person says so, reviewed or not. */
    fun inAlerts(s: FlareSource): String = when {
        s.tier == "approved" || s.tier == "private" -> "Shown on your map. Spoken only if you turn that on in Settings > Alerts."
        else -> "Not reviewed: shown on your map, spoken only if you turn that on in Settings > Alerts."
    }

    data class Use(val title: String, val sub: String, val allowed: Boolean)

    /** What the plugin can use, honestly: who asks it, with what. */
    fun uses(s: FlareSource): List<Use> {
        val out = ArrayList<Use>()
        when {
            s.ownSessionPath != null -> {
                out += Use("The area around you, while the app is open", "Rounded to about 5 km, to find alerts near you", true)
                out += Use("Your sign-in", "So what it shows stays yours", true)
            }
            s.isDirect -> out += Use("The area on your map, while the app is open", "Rounded to about 5 km. This phone asks it directly", true)
            else -> out += Use("The area on your map, through CommuteScout", "It never gets your exact location", true)
        }
        if (s.acceptsReports || s.canReport) out += Use("Reports you choose to send", "Only when you send one", true)
        out += Use(if (s.ownSessionPath != null) "Never your places or contacts" else "Never your places, contacts or account", "Plugins can't ask for these", false)
        return out
    }

    /** "Yes, 2 min ago", "No" or "Not asked yet", and whether it reads as good or bad. */
    fun answering(s: FlareSource, nowMs: Long): Pair<String, Boolean?> = when (s.ok) {
        true -> (s.lastOk?.let { "Yes, " + ago(it, nowMs) } ?: "Yes") to true
        false -> "No" to false
        null -> "Not asked yet" to null
    }

    fun alertsNow(n: Int) = when (n) { 0 -> "None"; 1 -> "1 alert"; else -> "%,d alerts".format(n) }

    /** A plugin's row on the Plugins page: added or not comes first, then whether it is showing. */
    fun rowValue(id: String, hidden: Set<String>, paused: Set<String>) = when {
        !isAdded(id, hidden, paused) -> "Not added"
        id in hidden -> "Off"
        else -> "On"
    }

    fun emptyLine(failed: Boolean) = if (failed) "The plugin list is not available right now." else "No plugin is listed yet."

    fun every(seconds: Int): String = when {
        seconds < 60 -> "Every $seconds s"
        seconds < 3600 -> "Every ${seconds / 60} min"
        else -> "Every ${seconds / 3600} h"
    }

    fun footnote(s: FlareSource): String {
        val from = s.attribution?.takeIf { it.isNotBlank() }
        return (if (from != null) "Data from $from. " else "") + "Verify an alert before you rely on it."
    }

    /** "just now", "5 min ago", "3 h ago" or "2 days ago" for an ISO time. */
    fun ago(iso: String, nowMs: Long): String {
        val t = runCatching { java.time.Instant.parse(iso).toEpochMilli() }.getOrNull()
            ?: runCatching { java.time.OffsetDateTime.parse(iso).toInstant().toEpochMilli() }.getOrNull() ?: return iso
        val s = (nowMs - t) / 1000
        return when {
            s < 60 -> "just now"
            s < 3600 -> "${s / 60} min ago"
            s < 86400 -> "${s / 3600} h ago"
            else -> "${s / 86400} days ago".replace(Regex("^1 days"), "1 day")
        }
    }

    /** The Remove button's steps, in place. */
    enum class RemoveStep { IDLE, CONFIRM, REMOVED }
}
