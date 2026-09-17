package com.commutescout.drive

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.util.Locale
import java.util.UUID

@Serializable
enum class PlaceKind { home, work, saved, recent }

@Serializable
data class Place(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val lat: Double,
    val lon: Double,
    val kind: PlaceKind,
    val savedAt: Long = System.currentTimeMillis(),
) {
    val shortName: String get() = name.substringBefore(",").trim()
}

/** Home, Work, favorites and recents, on this phone. */
class PlaceStore(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("cs.places", Context.MODE_PRIVATE)
    private val _places = MutableStateFlow(load())
    val places = _places.asStateFlow()

    val home: Place? get() = _places.value.firstOrNull { it.kind == PlaceKind.home }
    val work: Place? get() = _places.value.firstOrNull { it.kind == PlaceKind.work }
    val saved: List<Place> get() = _places.value.filter { it.kind == PlaceKind.saved }
    val recents: List<Place> get() = _places.value.filter { it.kind == PlaceKind.recent }.sortedByDescending { it.savedAt }

    fun set(kind: PlaceKind, name: String, lat: Double, lon: Double) {
        val rest = when (kind) {
            PlaceKind.home, PlaceKind.work -> _places.value.filter { it.kind != kind }
            else -> _places.value.filter { !(it.kind == kind && near(it, lat, lon)) }
        }
        save(rest + Place(name = name, lat = lat, lon = lon, kind = kind))
    }

    fun remove(place: Place) = save(_places.value.filter { it.id != place.id })
    fun removeAll() = save(emptyList())

    fun noteRecent(name: String, lat: Double, lon: Double) {
        val others = _places.value.filter { !(it.kind == PlaceKind.recent && near(it, lat, lon)) }
        val recents = others.filter { it.kind == PlaceKind.recent }.sortedByDescending { it.savedAt }.take(9)
        save(others.filter { it.kind != PlaceKind.recent } + recents + Place(name = name, lat = lat, lon = lon, kind = PlaceKind.recent))
    }

    private fun near(p: Place, lat: Double, lon: Double) =
        Math.abs(p.lat - lat) < 0.0005 && Math.abs(p.lon - lon) < 0.0005

    private fun save(list: List<Place>) {
        _places.value = list
        prefs.edit().putString("v1", Backend.json.encodeToString(list)).apply()
    }

    private fun load(): List<Place> =
        prefs.getString("v1", null)?.let { runCatching { Backend.json.decodeFromString<List<Place>>(it) }.getOrNull() } ?: emptyList()
}

/** Distances in the driver's units: the locale's by default, then whatever Settings says. */
object Units {
    var useMiles: Boolean
        get() = Engine.prefs.useMiles
        set(v) { Engine.prefs.useMiles = v }

    fun distance(meters: Double): String {
        if (useMiles) {
            val mi = meters / 1609.344
            if (mi < 0.1) return "${(meters * 3.28084 / 10).toInt() * 10} ft"
            return if (mi < 10) "%.1f mi".format(mi) else "${mi.toInt()} mi"
        }
        if (meters < 1000) return "${(meters / 10).toInt() * 10} m"
        val km = meters / 1000
        return if (km < 10) "%.1f km".format(km) else "${km.toInt()} km"
    }

    /** Distances as a voice says them. */
    fun spoken(meters: Double): String {
        if (useMiles) {
            val mi = meters / 1609.344
            return when {
                mi < 0.3 -> "a quarter mile"
                mi < 0.6 -> "half a mile"
                mi < 1.3 -> "one mile"
                else -> "${Math.round(mi)} miles"
            }
        }
        if (meters < 950) return "${(Math.round(meters / 100) * 100)} meters"
        val km = meters / 1000
        return if (km < 1.5) "one kilometer" else "${Math.round(km)} kilometers"
    }

    fun duration(seconds: Double): String {
        val m = (seconds / 60).toInt()
        if (m < 60) return "$m min"
        return "${m / 60} h ${m % 60} min"
    }
}
