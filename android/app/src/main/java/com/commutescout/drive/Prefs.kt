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
        val layerKinds = listOf(
            LayerKind("incident", "Incidents", "incident"),
            LayerKind("lane_closure", "Closures and lane work", "closure"),
            LayerKind("chain_control", "Chain controls", "chain"),
            LayerKind("wildfire", "Wildfires", "fire"),
            LayerKind("plugin", "Community reports", "plugin"),
        )
    }

    var theme by state(Theme.valueOf(p.getString("theme", "SYSTEM")!!)) { p.edit().putString("theme", it.name).apply() }
    var mapStyle by state(MapStyle.valueOf(p.getString("mapstyle", "AUTO")!!)) { p.edit().putString("mapstyle", it.name).apply() }
    var is3D by state(p.getBoolean("3d", true)) { p.edit().putBoolean("3d", it).apply() }
    var traffic by state(p.getBoolean("traffic", false)) { p.edit().putBoolean("traffic", it).apply() }
    var hiddenKinds by state(p.getStringSet("layers.off", emptySet())!!.toSet()) { p.edit().putStringSet("layers.off", it).apply() }
    var spokenAlerts by state(p.getBoolean("spokenalerts", true)) { p.edit().putBoolean("spokenalerts", it).apply() }
    var alertAheadMeters by state(p.getFloat("alertahead", 1500f).toDouble()) { p.edit().putFloat("alertahead", it.toFloat()).apply() }
    var showSpeedLimit by state(p.getBoolean("speedlimit", true)) { p.edit().putBoolean("speedlimit", it).apply() }
    var keepAwake by state(p.getBoolean("keepawake", true)) { p.edit().putBoolean("keepawake", it).apply() }
    var avoidTolls by state(p.getBoolean("avoid.tolls", false)) { p.edit().putBoolean("avoid.tolls", it).apply() }
    var avoidHighways by state(p.getBoolean("avoid.highways", false)) { p.edit().putBoolean("avoid.highways", it).apply() }
    var avoidFerries by state(p.getBoolean("avoid.ferries", false)) { p.edit().putBoolean("avoid.ferries", it).apply() }
    var useMiles by state(if (p.contains("miles")) p.getBoolean("miles", true) else localeMiles()) { p.edit().putBoolean("miles", it).apply() }

    fun isShown(kind: String) = kind !in hiddenKinds
    fun setShown(kind: String, on: Boolean) { hiddenKinds = if (on) hiddenKinds - kind else hiddenKinds + kind }

    /** The kinds parameter for /api/mapdata for what is switched on. */
    val apiKinds: String get() = layerKinds.filter { isShown(it.key) }.joinToString(",") { it.api }

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
