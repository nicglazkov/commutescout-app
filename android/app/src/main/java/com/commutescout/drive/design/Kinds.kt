package com.commutescout.drive.design

import com.commutescout.drive.PluginStyle
import com.commutescout.drive.RoadMarker

/**
 * How an alert looks in Day Glass+: its icon, its tone, its drawing and
 * the short line under its title. One answer per marker, so the alert,
 * the catalog, the see-more card and the event sheet all agree.
 */
data class AlertLook(
    val icon: String,
    val tone: Tone,
    val draw: DrawKind,
    /** From a plugin, not an official feed: drawn with the plugin's badge. */
    val community: Boolean = false,
    /** Group in the catalog: 0 act on it, 1 heads up, 2 good to know. */
    val group: Int = 1,
)

object Looks {
    val GROUPS = listOf("Act on it", "Heads up", "Good to know")

    fun of(m: RoadMarker): AlertLook = when (m.kind) {
        "incident" -> incident(m)
        "lane_closure" -> AlertLook("closure", Tone.HIGH, DrawKind.CLOSURE, group = 0)
        "chain_control" -> AlertLook("chain", Tone.HIGH, DrawKind.CHAIN, group = 0)
        "wildfire" -> AlertLook("fire", Tone.HIGH, DrawKind.FIRE, group = 0)
        "rwis" -> if (icy(m)) AlertLook("ice", Tone.MID, DrawKind.ICE) else AlertLook("ice", Tone.LOW, DrawKind.ICE, group = 2)
        "camera" -> AlertLook("camera", Tone.LOW, DrawKind.CAMERA, group = 2)
        "sign" -> AlertLook("sign", Tone.LOW, DrawKind.SIGN, group = 2)
        "toll" -> AlertLook("toll", Tone.LOW, DrawKind.TOLL, group = 2)
        "plugin" -> plugin(PluginStyle.category(m.flare_kind))
        else -> AlertLook("hazard", Tone.MID, DrawKind.HAZARD)
    }

    /** The look for an alert of [kind] when only the kind is known. */
    fun ofKind(kind: String?): AlertLook = of(RoadMarker(kind = kind ?: "incident", lat = 0.0, lon = 0.0))

    private fun plugin(category: String): AlertLook = when (category) {
        "police" -> AlertLook("police", Tone.LOW, DrawKind.POLICE, community = true, group = 2)
        "crash" -> AlertLook("crash", Tone.HIGH, DrawKind.CRASH, community = true, group = 0)
        "camera" -> AlertLook("camera", Tone.LOW, DrawKind.CAMERA, community = true, group = 2)
        "jam" -> AlertLook("traffic", Tone.MID, DrawKind.JAM, community = true)
        "weather" -> AlertLook("ice", Tone.MID, DrawKind.ICE, community = true)
        "closed" -> AlertLook("closure", Tone.HIGH, DrawKind.CLOSURE, community = true, group = 0)
        "chains" -> AlertLook("chain", Tone.HIGH, DrawKind.CHAIN, community = true, group = 0)
        else -> AlertLook("hazard", Tone.MID, DrawKind.HAZARD, community = true)
    }

    private fun incident(m: RoadMarker): AlertLook {
        val t = listOfNotNull(m.type, m.label, m.cls).joinToString(" ").lowercase()
        return when {
            "collision" in t || "crash" in t || "1179" in t || "1181" in t || "1182" in t || "1183" in t -> AlertLook("crash", Tone.HIGH, DrawKind.CRASH, group = 0)
            "fire" in t -> AlertLook("fire", Tone.HIGH, DrawKind.FIRE, group = 0)
            "closure" in t || "closed" in t -> AlertLook("closure", Tone.HIGH, DrawKind.CLOSURE, group = 0)
            "traffic" in t && ("slow" in t || "congest" in t) -> AlertLook("traffic", Tone.MID, DrawKind.JAM)
            else -> AlertLook("hazard", Tone.MID, DrawKind.HAZARD)
        }
    }

    private fun icy(m: RoadMarker): Boolean {
        val surf = (m.surface ?: "").lowercase()
        return "ice" in surf || "icy" in surf || "snow" in surf || "frost" in surf || (m.pave_c != null && m.pave_c <= 1.0)
    }
}
