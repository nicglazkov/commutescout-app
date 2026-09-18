package com.commutescout.drive

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * A Flare plugin the app knows about: one from the public catalog on
 * commutescout.com, or a private/unlisted one added here by URL and
 * polled directly from the phone.
 */
@Serializable
data class FlareSource(
    val id: String,
    val name: String,
    val base: String? = null,
    val token: String? = null,
    val refreshS: Int = 60,
    val canReport: Boolean = false,
    val canConfirm: Boolean = false,
    val attribution: String? = null,
    val trust: String? = null,
    val tier: String = "unreviewed",
    val count: Int = 0,
    val ok: Boolean? = null,
    // For the marketplace card (public catalog entries).
    val summary: String? = null,
    val coverage: List<Double>? = null,
    val kinds: List<String> = emptyList(),
    val acceptsReports: Boolean = false,
    // A catalog plugin that offers each signed-in person their own session
    // (handshake extensions.user_sessions): the path the phone polls itself.
    val ownSessionPath: String? = null,
) {
    val isDirect get() = base != null && ownSessionPath == null

    /** Where the plugin says it covers, in words. */
    val coverageLabel: String get() {
        val b = coverage ?: return "Coverage not stated"
        if (b.size != 4) return "Coverage not stated"
        val h = b[2] - b[0]; val w = b[3] - b[1]
        if (h >= 20 && w >= 50) return "Whole country"
        if (b[0] >= 32 && b[2] <= 36 && b[1] >= -121 && b[3] <= -114) return "Southern California"
        if (b[0] >= 32 && b[2] <= 42.5 && b[1] >= -125 && b[3] <= -114) return "California"
        return "${Math.round(h)}\u00B0 by ${Math.round(w)}\u00B0 area"
    }

    /** The kinds it shows, grouped into plain words. */
    val kindsLabel: String get() {
        val groups = LinkedHashSet<String>()
        for (k in kinds) groups.add(when {
            k.startsWith("POLICE") -> "police"; k.startsWith("CRASH") -> "crashes"; k.startsWith("HAZARD") -> "hazards"
            k.startsWith("JAM") -> "jams"; k.startsWith("ROAD_CLOSED") || k.startsWith("LANE") -> "closures"
            k.startsWith("WEATHER") -> "weather"; k.startsWith("CAMERA") -> "cameras"; k.startsWith("CHAINS") -> "chain controls"
            else -> "other"
        })
        return groups.joinToString(", ")
    }
}

@Serializable private data class Attribution(val name: String? = null, val url: String? = null)
@Serializable private data class PublicSource(val id: String, val name: String, val attribution: Attribution? = null, val trust: String? = null, val tier: String? = null, val count: Int? = null, val ok: Boolean? = null,
                                              val description: String? = null, val coverage: List<Double>? = null, val kinds: List<String>? = null, val capabilities: Map<String, Boolean>? = null,
                                              val base: String? = null)
@Serializable private data class UserSessions(val path: String? = null, val auth: String? = null, val idle_s: Int? = null, val poll_s: Int? = null)
@Serializable private data class Extensions(val user_sessions: UserSessions? = null)
@Serializable private data class SourcesResponse(val sources: List<PublicSource> = emptyList())
@Serializable private data class Handshake(val protocol: String, val id: String, val name: String, val capabilities: Map<String, Boolean>? = null,
                                           val refresh_s: Int? = null, val attribution: Attribution? = null, val auth: String? = null,
                                           val extensions: Extensions? = null)
@Serializable data class FlareAlert(val id: String, val kind: String, val lat: Double, val lon: Double, val description: String? = null,
                                    val report_ts: String? = null, val road_names: List<String>? = null, val n_confirmations: Int? = null,
                                    val reliability: Double? = null, val source_url: String? = null) {
    fun marker(source: FlareSource) = RoadMarker(
        kind = "plugin", lat = lat, lon = lon, id = "${source.id}:$id",
        label = description ?: kind.replace('_', ' ').lowercase().replaceFirstChar { it.uppercase() },
        location = road_names?.firstOrNull(), flare_kind = kind, source = source.name, description = description, reported = report_ts,
        tier = "private",
    )
}
@Serializable private data class FlareAlerts(val alerts: List<FlareAlert> = emptyList(), val ttl_s: Int? = null, val session: String? = null)

/**
 * The catalog and the driver's own sources. Public sources are drawn
 * through commutescout.com (mediated); direct sources are polled here
 * with the tile-snapped center, never the raw position.
 */
class SourcesStore(context: Context) {
    private val p = context.getSharedPreferences("cs.flare", Context.MODE_PRIVATE)
    // A private plugin's bearer token lives here, keyed by plugin id and
    // encrypted with a key from the Android keystore; the rest of the record
    // stays in the plain preferences. If the keystore is unusable the tokens
    // are kept in memory only and come back from the account on sign-in.
    private val secure: SharedPreferences = openSecure(context) ?: MemoryPrefs()
    private val _catalog = MutableStateFlow<List<FlareSource>>(emptyList())
    val catalog = _catalog.asStateFlow()
    private val _mine = MutableStateFlow(load())
    val mine = _mine.asStateFlow()
    private val _hidden = MutableStateFlow(p.getStringSet("hidden", emptySet())!!.toSet())
    val hidden = _hidden.asStateFlow()
    private val _direct = MutableStateFlow<List<RoadMarker>>(emptyList())
    val directMarkers = _direct.asStateFlow()
    // Catalog plugins polled by this phone for the signed-in person's own
    // session. Only bases from the commutescout.com catalog ever see the
    // account token; a plugin added by URL never does.
    private val _own = MutableStateFlow<List<FlareSource>>(emptyList())
    val ownSessionIds = MutableStateFlow<Set<String>>(emptySet())
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val jobs = HashMap<String, Job>()
    // Milliseconds to wait before the next poll of a source that failed,
    // answered 429 or 5xx: doubles each time up to ten minutes; absent after a success.
    private val backoff = HashMap<String, Long>()
    private val perSource = HashMap<String, List<RoadMarker>>()
    private var lastCenter: LatLon? = null

    init {
        scope.launch { loadCatalog() }
        _mine.value.forEach { schedule(it) }
    }

    fun isOn(id: String) = id !in _hidden.value
    fun setOn(id: String, on: Boolean) {
        _hidden.value = if (on) _hidden.value - id else _hidden.value + id
        p.edit().putStringSet("hidden", _hidden.value).apply()
        rebuild()
        pushToAccount()
    }

    // Account sync: Install on one device follows the account.
    var tokenProvider: (suspend () -> String?)? = null
    @Serializable private data class MePlugins(val plugins: MeInner = MeInner())
    @Serializable private data class MeInner(val off: List<String> = emptyList(), val private: List<MeMine> = emptyList())
    @Serializable private data class MeMine(val id: String, val name: String? = null, val base: String, val token: String? = null, val refresh_s: Int? = null)

    /** On sign-in: the account's switches replace this phone's, and the
     * account's private plugins (with their tokens) are added here. */
    suspend fun pullFromAccount() {
        val token = tokenProvider?.invoke() ?: return
        val (status, text) = runCatching { Backend.send("GET", "/api/me/plugins", token, null) }.getOrNull() ?: return
        if (status != 200) return
        val me = runCatching { Backend.json.decodeFromString<MePlugins>(text) }.getOrNull() ?: return
        _hidden.value = me.plugins.off.toSet()
        p.edit().putStringSet("hidden", _hidden.value).apply()
        val known = _mine.value.map { it.id }.toSet()
        val added = me.plugins.private.filter { it.id !in known }.map {
            FlareSource(it.id, it.name ?: it.id, it.base, it.token, max(15, it.refresh_s ?: 60), trust = "private", tier = "private")
        }
        if (added.isNotEmpty()) {
            _mine.value = _mine.value + added
            save()
            added.forEach { schedule(it) }
        }
        rebuild()
        Log.i("Sources", "account: ${_hidden.value.size} off, ${added.size} private plugin(s) added")
    }

    /** After a change: the account learns this phone's switches and its
     * private plugins, tokens included, so the next device has them too. */
    private fun pushToAccount() {
        scope.launch {
            val token = tokenProvider?.invoke() ?: return@launch
            val mineWire = _mine.value.mapNotNull { s -> s.base?.let { MeMine(s.id, s.name, it, s.token, s.refreshS) } }
            val body = Backend.json.encodeToString(MeInner(_hidden.value.sorted(), mineWire))
            runCatching { Backend.send("PUT", "/api/me/plugins", token, body) }
        }
    }

    suspend fun loadCatalog() {
        val r = runCatching { Backend.get<SourcesResponse>("/api/flare/sources", emptyMap()) }.getOrNull() ?: return
        _catalog.value = r.sources.map { FlareSource(it.id, it.name, attribution = it.attribution?.name, trust = it.trust, tier = it.tier ?: "unreviewed", count = it.count ?: 0, ok = it.ok,
            summary = it.description, coverage = it.coverage, kinds = it.kinds ?: emptyList(), acceptsReports = it.capabilities?.get("report") == true) }
        discoverOwnSessions(r.sources.mapNotNull { s -> s.base?.let { s.id to it } })
    }

    /** Catalog plugins whose handshake offers user sessions get polled here. */
    private suspend fun discoverOwnSessions(bases: List<Pair<String, String>>) {
        val found = ArrayList<FlareSource>()
        for ((id, base) in bases) {
            if (!base.startsWith("https://")) continue
            val text = runCatching {
                withContext(Dispatchers.IO) {
                    val b = Request.Builder().url("$base/flare/v1/handshake").header("Accept", "application/json")
                    Backend.http.newCall(b.build()).execute().use { r -> if (r.isSuccessful) r.body.string() else null }
                }
            }.getOrNull() ?: continue
            val h = runCatching { Backend.json.decodeFromString<Handshake>(text) }.getOrNull() ?: continue
            val us = h.extensions?.user_sessions ?: continue
            val path = us.path ?: continue
            if (us.auth != "firebase" || h.id != id) continue
            // An own session goes stale in seconds while the phone moves: its
            // cadence is the extension's poll_s, not the mediated refresh_s.
            found += FlareSource(h.id, h.name, base, null, max(15, minOf(us.poll_s ?: 15, 300)), h.capabilities?.get("report") == true,
                h.capabilities?.get("confirm") == true, h.attribution?.name, trust = "community", ownSessionPath = path)
        }
        _own.value = found
        ownSessionIds.value = found.map { it.id }.toSet()
        found.forEach { schedule(it) }
        if (found.isNotEmpty()) Log.i("Sources", "own sessions offered by: ${found.joinToString { it.id }}")
    }

    /** Adds a private or unlisted plugin by its base URL after a handshake. */
    suspend fun add(rawBase: String, token: String?): Boolean {
        val base = rawBase.trim().trimEnd('/')
        if (!base.startsWith("https://")) { _error.value = "The address must start with https://"; return false }
        return try {
            val text = withContext(Dispatchers.IO) {
                val b = Request.Builder().url("$base/flare/v1/handshake").header("Accept", "application/json")
                if (!token.isNullOrBlank()) b.header("Authorization", "Bearer $token")
                Backend.http.newCall(b.build()).execute().use { r ->
                    if (!r.isSuccessful) throw BackendError("The plugin answered ${r.code} to the handshake.")
                    r.body.string()
                }
            }
            val h = Backend.json.decodeFromString<Handshake>(text)
            if (!h.protocol.startsWith("flare/1")) { _error.value = "Not a Flare v1 plugin."; return false }
            val src = FlareSource(h.id, h.name, base, token?.takeIf { it.isNotBlank() }, max(15, h.refresh_s ?: 60),
                h.capabilities?.get("report") == true, h.capabilities?.get("confirm") == true, h.attribution?.name, "private", "private")
            _mine.value = _mine.value.filter { it.id != src.id } + src
            persist(); schedule(src)
            true
        } catch (e: Exception) {
            _error.value = e.message ?: "Could not reach the plugin."
            false
        }
    }

    fun remove(src: FlareSource) {
        _mine.value = _mine.value.filter { it.id != src.id }
        secure.edit().remove(src.id).apply()
        jobs.remove(src.id)?.cancel(); perSource.remove(src.id); backoff.remove(src.id)
        persist(); rebuild()
    }

    fun clearError() { _error.value = null }

    /** The map moved: direct sources are asked around the new (snapped) center. */
    fun view(center: LatLon) {
        val snapped = LatLon((center.lat * 20).roundToInt() / 20.0, (center.lon * 20).roundToInt() / 20.0)
        val last = lastCenter
        if (last != null && abs(last.lat - snapped.lat) < 1e-6 && abs(last.lon - snapped.lon) < 1e-6) return
        lastCenter = snapped
        _mine.value.forEach { s -> scope.launch { poll(s) } }
    }

    /** The pseudonym a direct plugin sees: stable per account and plugin, never the person. */
    fun reporter(src: FlareSource, uid: String): String =
        "r:" + MessageDigest.getInstance("SHA-256").digest("$uid|${src.id}".toByteArray()).joinToString("") { "%02x".format(it) }.take(24)

    /** A report straight to a direct plugin that accepts them. */
    suspend fun report(src: FlareSource, kind: String, lat: Double, lon: Double, description: String, uid: String) {
        val base = src.base ?: return
        if (!src.canReport) return
        val body = buildString {
            append("""{"kind":"$kind","lat":$lat,"lon":$lon,"ts":${JsonPrimitive(java.time.OffsetDateTime.now().toString())},"reporter":"${reporter(src, uid)}","client":"commutescout-android/${BuildConfig.VERSION_NAME}"""")
            if (description.isNotBlank()) append(""","description":${JsonPrimitive(description)}""")
            append("}")
        }
        withContext(Dispatchers.IO) {
            val b = Request.Builder().url("$base/flare/v1/report").post(body.toRequestBody("application/json".toMediaType()))
            src.token?.let { b.header("Authorization", "Bearer $it") }
            Backend.http.newCall(b.build()).execute().use { r -> if (r.code != 201 && r.code != 202) throw BackendError("${src.name} refused the report.") }
        }
    }

    /** Polls now, then every refreshS while the plugin answers, at the backed-off interval while it does not. */
    private fun schedule(src: FlareSource) {
        jobs[src.id]?.cancel()
        jobs[src.id] = scope.launch { while (isActive) { poll(src); delay(backoff[src.id] ?: src.refreshS * 1000L) } }
    }

    /** The plugin failed to answer: the next poll waits twice as long, up to ten minutes. */
    private fun failed(src: FlareSource, why: String) {
        val next = minOf(600_000L, (backoff[src.id] ?: src.refreshS * 1000L) * 2)
        backoff[src.id] = next
        Log.i("Sources", "${src.id}: $why, next poll in ${next / 1000} s")
    }

    private suspend fun poll(src: FlareSource) {
        val base = src.base ?: return
        val c = lastCenter ?: return
        if (!isOn(src.id)) return
        // Own session: the account token goes only to a catalog base; signed
        // out, the mediated copy from commutescout.com is what shows.
        val own = src.ownSessionPath
        val bearer = if (own != null) (tokenProvider?.invoke() ?: run { perSource.remove(src.id); rebuild(); return }) else src.token
        val path = own ?: "/flare/v1/alerts"
        val text = try {
            withContext(Dispatchers.IO) {
                val b = Request.Builder().url("$base$path?lat=%.3f&lon=%.3f&r=50000".format(java.util.Locale.US, c.lat, c.lon)).header("Accept", "application/json")
                bearer?.let { b.header("Authorization", "Bearer $it") }
                Backend.http.newCall(b.build()).execute().use { r ->
                    if (r.code == 429 || r.code >= 500) throw BackendError("answered ${r.code}", r.code)
                    if (r.isSuccessful) r.body.string() else null
                }
            }
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failed(src, e.message ?: "no answer"); return }
        backoff.remove(src.id)
        if (text == null) return
        val res = runCatching { Backend.json.decodeFromString<FlareAlerts>(text) }.getOrNull() ?: return
        perSource[src.id] = res.alerts.map { it.marker(src) }
        if (own != null) Log.i("Sources", "${src.id}: ${res.alerts.size} alerts, session=${res.session ?: "?"}")
        rebuild()
    }

    private fun rebuild() {
        _direct.value = (_mine.value + _own.value).filter { isOn(it.id) }.flatMap { perSource[it.id] ?: emptyList() }
    }
    private fun persist() {
        save()
        pushToAccount()
    }

    /** Writes the list without tokens; each token goes to the encrypted store. */
    private fun save() {
        val e = secure.edit()
        val stripped = _mine.value.map { s ->
            if (s.token != null) e.putString(s.id, s.token) else e.remove(s.id)
            s.copy(token = null)
        }
        e.apply()
        p.edit().putString("mine", Backend.json.encodeToString(stripped)).apply()
    }

    private fun load(): List<FlareSource> {
        val list = p.getString("mine", null)?.let { runCatching { Backend.json.decodeFromString<List<FlareSource>>(it) }.getOrNull() } ?: return emptyList()
        // A record saved by an earlier version still carries its token: move
        // it to the encrypted store once and rewrite the list without it.
        val legacy = list.filter { it.token != null }
        if (legacy.isNotEmpty()) {
            val e = secure.edit()
            legacy.forEach { e.putString(it.id, it.token) }
            e.apply()
            p.edit().putString("mine", Backend.json.encodeToString(list.map { it.copy(token = null) })).apply()
        }
        return list.map { it.copy(token = secure.getString(it.id, null)) }
    }

    private companion object {
        @Suppress("DEPRECATION")
        fun openSecure(context: Context): SharedPreferences? = runCatching {
            val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
            EncryptedSharedPreferences.create(context, "cs.flare.secure", key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        }.onFailure { Log.w("Sources", "encrypted store unavailable, tokens kept in memory", it) }.getOrNull()
    }
}

/** The in-memory stand-in for the encrypted store: only what this class uses. */
private class MemoryPrefs : SharedPreferences {
    private val m = HashMap<String, String>()
    override fun getString(key: String, defValue: String?) = m[key] ?: defValue
    override fun contains(key: String) = key in m
    override fun getAll(): MutableMap<String, *> = HashMap(m)
    override fun getStringSet(key: String, defValues: MutableSet<String>?) = defValues
    override fun getInt(key: String, defValue: Int) = defValue
    override fun getLong(key: String, defValue: Long) = defValue
    override fun getFloat(key: String, defValue: Float) = defValue
    override fun getBoolean(key: String, defValue: Boolean) = defValue
    override fun registerOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun unregisterOnSharedPreferenceChangeListener(l: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
        private val puts = HashMap<String, String>()
        private val removes = HashSet<String>()
        private var clear = false
        override fun putString(key: String, value: String?) = apply { if (value == null) removes.add(key) else puts[key] = value }
        override fun putStringSet(key: String, values: MutableSet<String>?) = this
        override fun putInt(key: String, value: Int) = this
        override fun putLong(key: String, value: Long) = this
        override fun putFloat(key: String, value: Float) = this
        override fun putBoolean(key: String, value: Boolean) = this
        override fun remove(key: String) = apply { removes.add(key) }
        override fun clear() = apply { clear = true }
        override fun commit(): Boolean { apply(); return true }
        override fun apply() {
            if (clear) m.clear()
            removes.forEach { m.remove(it) }
            m.putAll(puts)
        }
    }
}
