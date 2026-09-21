package com.commutescout.drive

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/**
 * Everything a driver can set. Stored per device; each value is Compose
 * state so screens update the moment it changes.
 */
class Prefs(context: Context) {
    private val p: SharedPreferences = context.getSharedPreferences("cs.prefs", Context.MODE_PRIVATE)

    enum class Theme(val label: String) { SYSTEM("System"), LIGHT("Light"), DARK("Dark") }
    enum class MapStyle(val label: String) {
        AUTO("Match theme"), LIGHT("Light"), DARK("Dark"), OUTDOORS("Outdoors");

        fun serverStyle(dark: Boolean): String = when (this) {
            AUTO -> if (dark) "alidade_smooth_dark" else "alidade_smooth"
            LIGHT -> "alidade_smooth"
            DARK -> "alidade_smooth_dark"
            OUTDOORS -> "outdoors"
        }
    }

    data class LayerKind(val key: String, val label: String, val api: String)

    companion object {
        /**
         * Every layer the website offers. The api name is what
         * /api/mapdata's kinds parameter takes, which is not always the
         * kind the server sends back: closure returns lane_closure,
         * chain returns chain_control and fire returns wildfire.
         */
        val layerKinds = listOf(
            LayerKind("incident", "Incidents", "incident"),
            LayerKind("lane_closure", "Closures and lane work", "closure"),
            LayerKind("chain_control", "Chain controls", "chain"),
            LayerKind("wildfire", "Wildfires", "fire"),
            LayerKind("toll", "Toll prices", "toll"),
            LayerKind("plugin", "Community reports", "plugin"),
            LayerKind("rwis", "Weather stations", "rwis"),
            LayerKind("sign", "Message signs", "sign"),
            LayerKind("camera", "Cameras", "camera"),
        )

        /** The two the website starts with switched off, being large and noisy. */
        val offByDefault = setOf("toll", "camera")

        /**
         * Kinds the app never asks for per viewport. Nationwide they
         * are tens of thousands of points and they carry no line
         * geometry, so the session snapshot is the whole story, as on
         * the website.
         */
        val snapshotOnlyKinds = setOf("camera", "sign", "rwis")
    }

    /** Back to defaults, for UI tests that must start the same way every run. */
    fun resetForTests() {
        p.edit().clear().apply()
        theme = Theme.SYSTEM; mapStyle = MapStyle.AUTO; is3D = true; traffic = false; hiddenKinds = offByDefault
        spokenAlerts = true; alertAheadMeters = 1500.0; showSpeedLimit = true; keepAwake = true
        avoidTolls = false; avoidHighways = false; avoidFerries = false; stripAheadMeters = 16093.0
        advancedAlerts = false; alertRulesRaw = ""; useMiles = true
    }

    var theme by state(Theme.valueOf(p.getString("theme", "SYSTEM")!!)) { p.edit().putString("theme", it.name).apply() }
    var mapStyle by state(MapStyle.valueOf(p.getString("mapstyle", "AUTO")!!)) { p.edit().putString("mapstyle", it.name).apply() }
    var is3D by state(p.getBoolean("3d", true)) { p.edit().putBoolean("3d", it).apply() }
    var traffic by state(p.getBoolean("traffic", false)) { p.edit().putBoolean("traffic", it).apply() }
    var hiddenKinds by state(savedHiddenKinds()) { p.edit().putStringSet("layers.off", it).apply() }
    var spokenAlerts by state(p.getBoolean("spokenalerts", true)) { p.edit().putBoolean("spokenalerts", it).apply() }
    var alertAheadMeters by state(p.getFloat("alertahead", 1500f).toDouble()) { p.edit().putFloat("alertahead", it.toFloat()).apply() }
    var showSpeedLimit by state(p.getBoolean("speedlimit", true)) { p.edit().putBoolean("speedlimit", it).apply() }
    var keepAwake by state(p.getBoolean("keepawake", true)) { p.edit().putBoolean("keepawake", it).apply() }
    var avoidTolls by state(p.getBoolean("avoid.tolls", false)) { p.edit().putBoolean("avoid.tolls", it).apply() }
    var avoidHighways by state(p.getBoolean("avoid.highways", false)) { p.edit().putBoolean("avoid.highways", it).apply() }
    var avoidFerries by state(p.getBoolean("avoid.ferries", false)) { p.edit().putBoolean("avoid.ferries", it).apply() }
    var stripAheadMeters by state(p.getFloat("alerts.strip", 16093f).toDouble()) { p.edit().putFloat("alerts.strip", it.toFloat()).apply() }
    var advancedAlerts by state(p.getBoolean("alerts.advanced", false)) { p.edit().putBoolean("alerts.advanced", it).apply() }
    var alertRulesRaw by state(p.getString("alerts.rules", "")!!) { p.edit().putString("alerts.rules", it).apply() }
    var useMiles by state(if (p.contains("miles")) p.getBoolean("miles", true) else localeMiles()) { p.edit().putBoolean("miles", it).apply() }

    /**
     * Roughly where the driver was when the app last held a snapshot.
     *
     * It is read at launch to aim the next one, so the dots start
     * loading immediately rather than waiting for a location fix. It
     * moves only when the driver leaves the area a snapshot covers,
     * which is hundreds of kilometres wide, so this is not a trail.
     */
    var lastCenter: LatLon?
        get() {
            if (!p.contains("last.lat")) return null
            return LatLon(p.getFloat("last.lat", 0f).toDouble(), p.getFloat("last.lon", 0f).toDouble())
        }
        set(v) {
            if (v == null) p.edit().remove("last.lat").remove("last.lon").apply()
            else p.edit().putFloat("last.lat", v.lat.toFloat()).putFloat("last.lon", v.lon.toFloat()).apply()
        }

    /**
     * Which layers start switched off.
     *
     * A layer added after a release cannot appear in a set saved by an
     * older one, so someone upgrading would find every new layer on,
     * cameras included. The ones the website starts off are added to
     * what is hidden, once, and never again after that.
     */
    private fun savedHiddenKinds(): Set<String> {
        val saved = p.getStringSet("layers.off", null)?.toSet() ?: return offByDefault
        if (p.getBoolean("layers.roadside", false)) return saved
        p.edit().putBoolean("layers.roadside", true).apply()
        return saved + offByDefault
    }

    fun isShown(kind: String) = kind !in hiddenKinds
    fun setShown(kind: String, on: Boolean) { hiddenKinds = if (on) hiddenKinds - kind else hiddenKinds + kind }

    /**
     * How one kind of alert is announced: at what distance, whether it
     * repeats closer, and whether it is spoken at all.
     */
    @kotlinx.serialization.Serializable
    data class AlertRule(val enabled: Boolean = true, val speak: Boolean = true, val firstMeters: Double = 1500.0, val repeatMeters: Double = 0.0)

    val alertKinds = listOf(
        "incident" to "Incidents", "lane_closure" to "Closures and lane work", "chain_control" to "Chain controls",
        "wildfire" to "Wildfires", "police" to "Police reports", "hazard" to "Hazard and crash reports", "plugin" to "Other community reports",
    )

    var alertRules: Map<String, AlertRule>
        get() = runCatching { Backend.json.decodeFromString<Map<String, AlertRule>>(alertRulesRaw) }.getOrDefault(emptyMap())
        set(v) { alertRulesRaw = Backend.json.encodeToString(kotlinx.serialization.serializer<Map<String, AlertRule>>(), v) }

    fun rule(kind: String): AlertRule =
        if (!advancedAlerts) AlertRule(true, spokenAlerts, alertAheadMeters, 0.0) else alertRules[kind] ?: AlertRule()

    fun setRule(kind: String, r: AlertRule) { alertRules = alertRules + (kind to r) }

    /** The rule group for a marker: community reports split by what they are. */
    fun ruleKind(m: RoadMarker): String {
        if (m.kind != "plugin") return m.kind
        val k = (m.flare_kind ?: "").uppercase()
        return when {
            k.startsWith("POLICE") -> "police"
            k.startsWith("HAZARD") || k.startsWith("CRASH") -> "hazard"
            else -> "plugin"
        }
    }

    /**
     * The kinds parameter for /api/mapdata for what is switched on.
     * The snapshot-only kinds stay out of it: asking for them per
     * viewport would triple the size of a call whose real job is to
     * bring back the closure and toll lines the snapshot drops.
     */
    val apiKinds: String get() = layerKinds
        .filter { it.key !in snapshotOnlyKinds && isShown(it.key) }
        .joinToString(",") { it.api }

    /** Valhalla costing options from the route settings; empty when defaults. */
    val costingOptions: Map<String, Any>
        get() {
            val auto = mutableMapOf<String, Any>()
            if (avoidTolls) auto["use_tolls"] = 0
            if (avoidHighways) auto["use_highways"] = 0
            if (avoidFerries) auto["use_ferry"] = 0
            return if (auto.isEmpty()) emptyMap() else mapOf("auto" to auto)
        }

    /** A fingerprint of everything that changes how routes are asked for. */
    val routingKey: String get() = "$avoidTolls|$avoidHighways|$avoidFerries|$useMiles"

    private fun localeMiles(): Boolean = Locale.getDefault().country in setOf("US", "GB", "LR", "MM")

    private fun <T> state(initial: T, save: (T) -> Unit) = object : kotlin.properties.ReadWriteProperty<Any?, T> {
        private var s = mutableStateOf(initial)
        override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = s.value
        override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) { s.value = value; save(value) }
    }
}
