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
    private val appContext: Context = context.applicationContext ?: context
    private val p: SharedPreferences = context.getSharedPreferences("cs.prefs", Context.MODE_PRIVATE)
    /** A phone that had this app before the first-run screen counts as past it. */
    private val upgraded = p.all.isNotEmpty() && !p.contains("welcome.done")

    enum class Theme(val label: String) { SYSTEM("Match my phone"), LIGHT("Light"), DARK("Dark") }
    /**
     * The four looks the app offers, in order. Positron and Bright are
     * OpenFreeMap's styles, read from its tiles while online; without a
     * signal the map falls back to Light, drawn from the file saved on
     * the phone. Slate and Gray are CommuteScout's own. OUTDOORS is the
     * old stored name for Gray, kept so a saved choice still reads.
     */
    enum class MapStyle(val label: String) {
        POSITRON("Positron"), BRIGHT("Bright"), SLATE("Slate"), OUTDOORS("Gray");

        /** The bundled style for this choice in the given theme: Positron, the default, dims at night. */
        fun flavor(dark: Boolean): String = when (this) {
            POSITRON -> if (dark) "dark" else "positron"
            BRIGHT -> "bright"
            SLATE -> "slate"
            OUTDOORS -> "grayscale"
        }

        companion object {
            /** A saved choice: one that is no longer offered becomes Positron. */
            fun saved(name: String?): MapStyle = entries.firstOrNull { it.name == name } ?: POSITRON
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
            LayerKind("plugin", "Plugin alerts", "plugin"),
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
        theme = Theme.SYSTEM; mapStyle = MapStyle.POSITRON; is3D = false; traffic = false; hiddenKinds = offByDefault; sourceFilter = SourceFilter.ALL
        spokenAlerts = true; alertAheadMeters = 1500.0; showSpeedLimit = true; keepAwake = true
        avoidTolls = false; avoidHighways = false; avoidFerries = false; stripAheadMeters = 16093.0
        advancedAlerts = false; alertRulesRaw = ""; distanceUnit = DistanceChoice.MILES
        clockUnit = ClockChoice.AUTO; tempUnit = TempChoice.AUTO
        alertDelivery = AlertDelivery.VOICE; alertChipsOff = AlertChips.offByDefault; pluginAlertsOff = emptySet(); speakPluginAlerts = false
        // UI tests start on the map, not on the first-run screen.
        welcomeDone = true
        voiceName = ""; voiceEngine = ""; voiceRate = 1f; voicePitch = 1f
    }

    // A name dropped in an update must not be a crash loop at launch.
    var theme by state(runCatching { Theme.valueOf(p.getString("theme", "SYSTEM")!!) }.getOrDefault(Theme.SYSTEM)) { p.edit().putString("theme", it.name).apply() }
    var mapStyle by state(MapStyle.saved(p.getString("mapstyle", null))) { p.edit().putString("mapstyle", it.name).apply() }
    init {
        // Dark was a map style; the dark theme gives that driver the same map now.
        if (p.getString("mapstyle", null) == "DARK") {
            if (theme == Theme.SYSTEM) theme = Theme.DARK
            mapStyle = MapStyle.POSITRON
        }
    }
    var is3D by state(p.getBoolean("3d", false)) { p.edit().putBoolean("3d", it).apply() }
    var traffic by state(p.getBoolean("traffic", false)) { p.edit().putBoolean("traffic", it).apply() }
    /** Save the map along a route when a trip starts, on Wi-Fi. */
    var mapAutoSave by state(p.getBoolean("map.autosave", true)) { p.edit().putBoolean("map.autosave", it).apply() }
    var hiddenKinds by state(savedHiddenKinds()) { p.edit().putStringSet("layers.off", it).apply() }
    var sourceFilter by state(runCatching { SourceFilter.valueOf(p.getString("layers.sources", "ALL")!!) }.getOrDefault(SourceFilter.ALL)) {
        p.edit().putString("layers.sources", it.name).apply()
    }
    init {
        // Plugin alerts had their own layer switch. The source filter on the
        // Plugins page does that job now, so a driver who hid them stays hidden.
        if ("plugin" in hiddenKinds) {
            hiddenKinds = hiddenKinds - "plugin"
            if (sourceFilter == SourceFilter.ALL) sourceFilter = SourceFilter.OFFICIAL
        }
    }
    /** How alerts reach the driver: spoken, a chime, or only on screen. */
    var alertDelivery by state(runCatching { AlertDelivery.valueOf(p.getString("alerts.delivery", null)!!) }.getOrElse {
        if (p.getBoolean("spokenalerts", true)) AlertDelivery.VOICE else AlertDelivery.SILENT
    }) { p.edit().putString("alerts.delivery", it.name).apply() }
    /** Alerts are spoken (the old switch, kept for the engine and the summary). */
    var spokenAlerts: Boolean
        get() = alertDelivery == AlertDelivery.VOICE
        set(v) { alertDelivery = if (v) AlertDelivery.VOICE else AlertDelivery.SILENT }
    /** Kinds of official alert that do not alert (they still show on the map), by [AlertChips] key. */
    var alertChipsOff by state(p.getStringSet("alerts.chips.off", null)?.toSet() ?: AlertChips.offByDefault) { p.edit().putStringSet("alerts.chips.off", it).apply() }
    /** Plugins, by source id, whose alerts do not alert. Their markers stay on the map. */
    var pluginAlertsOff by state(p.getStringSet("alerts.plugins.off", null)?.toSet() ?: emptySet()) { p.edit().putStringSet("alerts.plugins.off", it).apply() }
    /** Plugin alerts are spoken too; off, they chime. */
    var speakPluginAlerts by state(p.getBoolean("alerts.plugins.speak", false)) { p.edit().putBoolean("alerts.plugins.speak", it).apply() }
    /** The first-run screen is done (or skipped). */
    var welcomeDone by state(p.getBoolean("welcome.done", false) || upgraded) { p.edit().putBoolean("welcome.done", it).apply() }
    var alertAheadMeters by state(p.getFloat("alertahead", 1500f).toDouble()) { p.edit().putFloat("alertahead", it.toFloat()).apply() }
    var showSpeedLimit by state(p.getBoolean("speedlimit", true)) { p.edit().putBoolean("speedlimit", it).apply() }
    var keepAwake by state(p.getBoolean("keepawake", true)) { p.edit().putBoolean("keepawake", it).apply() }
    var avoidTolls by state(p.getBoolean("avoid.tolls", false)) { p.edit().putBoolean("avoid.tolls", it).apply() }
    var avoidHighways by state(p.getBoolean("avoid.highways", false)) { p.edit().putBoolean("avoid.highways", it).apply() }
    var avoidFerries by state(p.getBoolean("avoid.ferries", false)) { p.edit().putBoolean("avoid.ferries", it).apply() }
    var stripAheadMeters by state(p.getFloat("alerts.strip", 16093f).toDouble()) { p.edit().putFloat("alerts.strip", it.toFloat()).apply() }
    var advancedAlerts by state(p.getBoolean("alerts.advanced", false)) { p.edit().putBoolean("alerts.advanced", it).apply() }
    var alertRulesRaw by state(p.getString("alerts.rules", "")!!) { p.edit().putString("alerts.rules", it).apply() }
    /** Distance: match the phone's region, or miles or kilometers. An old Miles or Kilometers pick carries over. */
    var distanceUnit by state(runCatching { DistanceChoice.valueOf(p.getString("units.distance", null)!!) }.getOrElse {
        if (p.contains("miles")) (if (p.getBoolean("miles", true)) DistanceChoice.MILES else DistanceChoice.KM) else DistanceChoice.AUTO
    }) { p.edit().putString("units.distance", it.name).apply(); syncUnitStyle() }
    var clockUnit by state(runCatching { ClockChoice.valueOf(p.getString("units.clock", "AUTO")!!) }.getOrDefault(ClockChoice.AUTO)) {
        p.edit().putString("units.clock", it.name).apply(); syncUnitStyle()
    }
    var tempUnit by state(runCatching { TempChoice.valueOf(p.getString("units.temp", "AUTO")!!) }.getOrDefault(TempChoice.AUTO)) {
        p.edit().putString("units.temp", it.name).apply(); syncUnitStyle()
    }
    /** What the phone itself says, read each time: the driver can change it while the app runs. */
    val phoneMiles: Boolean get() = localeMiles()
    val phone24: Boolean get() = runCatching { android.text.format.DateFormat.is24HourFormat(appContext) }.getOrDefault(false)
    val phoneFahrenheit: Boolean get() = runCatching {
        androidx.core.text.util.LocalePreferences.getTemperatureUnit() == androidx.core.text.util.LocalePreferences.TemperatureUnit.FAHRENHEIT
    }.getOrElse { UnitRules.regionFahrenheit(Locale.getDefault().country) }
    var useMiles: Boolean
        get() = UnitRules.miles(distanceUnit, phoneMiles)
        set(v) { distanceUnit = if (v) DistanceChoice.MILES else DistanceChoice.KM }
    val use24h: Boolean get() = UnitRules.h24(clockUnit, phone24)
    val useFahrenheit: Boolean get() = UnitRules.fahrenheit(tempUnit, phoneFahrenheit)
    /** Hands the resolved clock and temperature to the formatters that cannot read Prefs. */
    fun syncUnitStyle() { UnitStyle.h24 = use24h; UnitStyle.fahrenheit = useFahrenheit }
    /**
     * The voice for alerts and turn instructions, by the engine's name
     * for it; empty picks the best one on the phone for the language.
     * The engine is a package name; empty is the system's default.
     */
    var voiceName by state(p.getString("voice.name", "")!!) { p.edit().putString("voice.name", it).apply() }
    var voiceEngine by state(p.getString("voice.engine", "")!!) { p.edit().putString("voice.engine", it).apply() }
    var voiceRate by state(p.getFloat("voice.rate", 1f)) { p.edit().putFloat("voice.rate", it).apply() }
    var voicePitch by state(p.getFloat("voice.pitch", 1f)) { p.edit().putFloat("voice.pitch", it).apply() }

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

    /** Official sources, plugins, or both: one choice over the layer
     *  switches, which keep what they were set to. */
    enum class SourceFilter(val label: String) {
        ALL("Everything"), OFFICIAL("Official"), PLUGINS("Plugins");
        fun allows(kind: String) = when (this) { ALL -> true; OFFICIAL -> kind != "plugin"; PLUGINS -> kind == "plugin" }
    }

    /** The layer's own switch, whatever the source filter says. */
    fun isChosen(kind: String) = kind !in hiddenKinds

    /** Whether the kind is drawn: its switch is on and the filter lets it through. */
    fun isShown(kind: String) = isChosen(kind) && sourceFilter.allows(kind)
    fun setShown(kind: String, on: Boolean) { hiddenKinds = if (on) hiddenKinds - kind else hiddenKinds + kind }

    /**
     * How one kind of alert is announced: at what distance, whether it
     * repeats closer, and whether it is spoken at all.
     */
    @kotlinx.serialization.Serializable
    data class AlertRule(val enabled: Boolean = true, val speak: Boolean = true, val firstMeters: Double = 1500.0, val repeatMeters: Double = 0.0,
                         /** A short chime when it is not spoken. */ val chime: Boolean = false)

    val alertKinds = listOf(
        "incident" to "Incidents", "lane_closure" to "Closures and lane work", "chain_control" to "Chain controls",
        "wildfire" to "Wildfires", "police" to "Police reports", "hazard" to "Hazard and crash reports", "plugin" to "Other community reports",
    )

    // Decoded once per change, not once per marker per fix: the engine
    // asks for a rule hundreds of times a second with advanced alerts on.
    private var rulesCache: Pair<String, Map<String, AlertRule>>? = null
    var alertRules: Map<String, AlertRule>
        get() {
            val raw = alertRulesRaw
            rulesCache?.let { if (it.first == raw) return it.second }
            val m = runCatching { Backend.json.decodeFromString<Map<String, AlertRule>>(raw) }.getOrDefault(emptyMap())
            rulesCache = raw to m
            return m
        }
        set(v) { alertRulesRaw = Backend.json.encodeToString(kotlinx.serialization.serializer<Map<String, AlertRule>>(), v) }

    fun rule(kind: String): AlertRule =
        if (!advancedAlerts) AlertRule(true, spokenAlerts, alertAheadMeters, 0.0) else alertRules[kind] ?: AlertRule()

    /**
     * The rule the engine uses for one marker: the per-kind rule, then
     * the alert chips, the plugin switches and how alerts reach the
     * driver (voice, a chime or silent). Plugin alerts chime unless
     * Speak plugin alerts is on.
     */
    fun ruleFor(m: RoadMarker): AlertRule = AlertChips.apply(rule(ruleKind(m)), m, alertDelivery, alertChipsOff, pluginAlertsOff, speakPluginAlerts)

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

    private fun localeMiles(): Boolean = UnitRules.regionMiles(Locale.getDefault().country)

    private fun <T> state(initial: T, save: (T) -> Unit) = object : kotlin.properties.ReadWriteProperty<Any?, T> {
        private var s = mutableStateOf(initial)
        override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = s.value
        override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) { s.value = value; save(value) }
    }
}
