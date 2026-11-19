package com.commutescout.drive

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.stadiamaps.ferrostar.core.location.NavigationLocationProviding
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * How hard the app works in each situation, in one place (docs/battery.md).
 * The same rules as the iPhone app's PowerPolicy.swift. Plain arithmetic,
 * so the unit tests can hold it.
 */
object Power {
    data class LocationSetting(val priority: Int, val intervalMs: Long, val minDistanceM: Float)

    /**
     * What the GPS is asked for. A trip gets one high-accuracy fix a
     * second, as before; the 5 m filter only drops the fixes a parked
     * phone makes from noise. Driving with no trip gets the same rate
     * with a 10 m filter. A phone that is not moving gets a fix every
     * two seconds at most, and none while it stays put.
     */
    fun location(navigating: Boolean, driving: Boolean): LocationSetting = when {
        navigating -> LocationSetting(Priority.PRIORITY_HIGH_ACCURACY, 1000L, 5f)
        driving -> LocationSetting(Priority.PRIORITY_HIGH_ACCURACY, 1000L, 10f)
        else -> LocationSetting(Priority.PRIORITY_HIGH_ACCURACY, 2000L, 15f)
    }

    /**
     * With a distance filter a phone stopped at a light gets no fixes, so
     * a silent GPS is not a lost one. A car braking to a stop sends its
     * last fix at up to about 8 m/s; only one that went quiet faster than
     * that (a tunnel) has an unknown speed.
     */
    fun speedUnknownAfterSilence(lastSpeed: Double): Boolean = lastSpeed > 8.0

    /** The map draws at 30 frames a second unless a finger is on it (null: the display's most). */
    const val CRUISING_FPS = 30
    fun mapFps(touching: Boolean): Int? = if (touching) null else CRUISING_FPS
    /** How long the full rate lasts after the finger lifts, for the fling. */
    const val TOUCH_LINGER_MS = 1500L

    /** A new alert's ring breathes this long, then holds still. */
    const val RING_PULSE_MS = 8000L

    /**
     * Every timed fetch runs on one beat aligned to the clock, so they
     * leave together and the cellular radio wakes once a minute, not
     * once per timer.
     */
    const val BEAT_MS = 60_000L

    /** Milliseconds from `now` to the next beat at least `everyMs` apart. */
    fun untilNextBeat(now: Long, everyMs: Long = BEAT_MS): Long {
        val step = maxOf(BEAT_MS, ((everyMs + BEAT_MS - 1) / BEAT_MS) * BEAT_MS)
        return (now / step) * step + step - now
    }

    /** A plugin's own cadence, put on the beat: its dots only draw on the map. */
    fun pluginEveryMs(requestedS: Int): Long = maxOf(BEAT_MS, ((requestedS * 1000L + BEAT_MS - 1) / BEAT_MS) * BEAT_MS)

    /** The country-wide snapshot: less often on the move, when the viewport fetch carries what is near. */
    fun snapshotEveryMs(moving: Boolean): Long = if (moving) 30 * 60_000L else 10 * 60_000L

    /** Set by the view model as the trip and driving state change. */
    val setting = MutableStateFlow(location(navigating = false, driving = false))
    @Volatile var moving = false

    fun apply(navigating: Boolean, driving: Boolean) {
        moving = navigating || driving
        val s = location(navigating, driving)
        if (setting.value != s) {
            android.util.Log.i("Power", "gps: priority ${s.priority}, ${s.intervalMs} ms, ${s.minDistanceM} m")
            setting.value = s
        }
    }
}

/**
 * The phone's location, asked for only as much as the moment needs
 * (Power.location). Ferrostar's FusedNavigationLocationProvider always
 * asks for high accuracy every second with no distance filter.
 */
class LeanLocationProvider(context: Context) : NavigationLocationProviding {
    private val client = LocationServices.getFusedLocationProviderClient(context)

    @SuppressLint("MissingPermission")
    override suspend fun lastLocation(): Location? = suspendCancellableCoroutine { c ->
        client.lastLocation.addOnSuccessListener { c.resume(it) }.addOnFailureListener { c.resume(null) }
    }

    /** The interval asked by the caller is a floor; the setting decides the rest. */
    @OptIn(ExperimentalCoroutinesApi::class)
    override fun locationUpdates(intervalMillis: Long): Flow<Location> =
        Power.setting.flatMapLatest { s -> updates(s.priority, maxOf(intervalMillis, s.intervalMs), s.minDistanceM) }

    @SuppressLint("MissingPermission")
    private fun updates(priority: Int, intervalMs: Long, minDistance: Float): Flow<Location> = callbackFlow {
        val request = LocationRequest.Builder(priority, intervalMs).setMinUpdateDistanceMeters(minDistance).build()
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) { result.lastLocation?.let { trySend(it) } }
        }
        client.requestLocationUpdates(request, callback, android.os.Looper.getMainLooper())
        awaitClose { client.removeLocationUpdates(callback) }
    }
}
