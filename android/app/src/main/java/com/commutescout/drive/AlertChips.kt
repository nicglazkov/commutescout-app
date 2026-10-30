package com.commutescout.drive

import com.commutescout.drive.design.Looks

/** How alerts reach the driver. */
enum class AlertDelivery(val label: String) { VOICE("Voice"), SOUND("Sound"), SILENT("Silent") }

/**
 * The alert chips on the Alerts page: official kinds in the three
 * groups the alerts themselves use (act on it, heads up, good to know).
 * A chip turned off stops the alert, never the marker on the map.
 * Plugin alerts are not here: they have their own section and switches.
 */
object AlertChips {
    data class Chip(val key: String, val label: String)
    data class Tier(val label: String, val chips: List<Chip>)

    val tiers = listOf(
        Tier("Act on it", listOf(Chip("crash", "Crashes"), Chip("closure", "Closures"), Chip("chain", "Chain controls"), Chip("fire", "Wildfires"))),
        Tier("Heads up", listOf(Chip("traffic", "Slow traffic"), Chip("ice", "Icy roads"), Chip("hazard", "Road hazards"))),
        Tier("Good to know", listOf(Chip("sign", "Message signs"), Chip("camera", "Speed cameras"), Chip("toll", "Toll prices"))),
    )
    val keys: List<String> = tiers.flatMap { t -> t.chips.map { it.key } }

    /** Large and noisy, as on the website: off until the driver wants them. */
    val offByDefault = setOf("camera", "toll")

    /** The chip an official marker falls under; null for plugin markers. Its icon names its kind. */
    fun keyOf(m: RoadMarker): String? {
        if (m.kind == "plugin") return null
        val icon = Looks.of(m).icon
        return icon.takeIf { it in keys } ?: "hazard"
    }

    /** The chips' tier index, the same grouping the alerts are drawn with. */
    fun tierOf(key: String): Int = tiers.indexOfFirst { t -> t.chips.any { it.key == key } }

    /**
     * One marker's rule after the Alerts page: chips and plugin switches
     * can turn it off; the delivery picks voice, a chime or nothing.
     * A plugin alert is spoken only with [speakPlugins]; otherwise it
     * chimes where an official one would speak.
     */
    fun apply(base: Prefs.AlertRule, m: RoadMarker, delivery: AlertDelivery, chipsOff: Set<String>, pluginsOff: Set<String>, speakPlugins: Boolean): Prefs.AlertRule {
        val plugin = m.kind == "plugin"
        val off = if (plugin) PluginStyle.sourceId(m) in pluginsOff else keyOf(m) in chipsOff
        val voice = base.speak && delivery == AlertDelivery.VOICE && (!plugin || speakPlugins)
        val chime = !voice && when (delivery) {
            AlertDelivery.SOUND -> true
            AlertDelivery.VOICE -> base.speak
            AlertDelivery.SILENT -> false
        }
        return base.copy(enabled = base.enabled && !off, speak = voice, chime = chime)
    }
}
