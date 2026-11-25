package com.commutescout.drive

import java.time.Instant
import java.time.ZoneId
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * Whether the sun is up at a place, for the "Dark after sunset" theme.
 * A short almanac formula, good to about a minute at ordinary
 * latitudes, with no network and no table.
 */
object Daylight {
    /** The sun counts as up above this, in degrees: its disc and the air's bending put sunrise at -0.833. */
    const val horizon = -0.833

    /** The sun's height over the horizon in degrees. */
    fun sunElevation(lat: Double, lon: Double, epochMs: Long): Double {
        val n = epochMs / 86_400_000.0 - 10957.5            // days since noon, 1 Jan 2000 UTC
        val meanLon = Math.toRadians(mod(280.460 + 0.9856474 * n, 360.0))
        val anomaly = Math.toRadians(mod(357.528 + 0.9856003 * n, 360.0))
        val ecliptic = meanLon + Math.toRadians(1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly))
        val tilt = Math.toRadians(23.439 - 0.0000004 * n)
        val rightAscension = atan2(cos(tilt) * sin(ecliptic), cos(ecliptic))
        val declination = asin(sin(tilt) * sin(ecliptic))
        val siderealHours = mod(18.697374558 + 24.06570982441908 * n, 24.0)
        val hourAngle = Math.toRadians(siderealHours * 15 + lon) - rightAscension
        val la = Math.toRadians(lat)
        return Math.toDegrees(asin(sin(la) * sin(declination) + cos(la) * cos(declination) * cos(hourAngle)))
    }

    /**
     * True in daylight. With a position it follows the sun there;
     * without one it falls back to the clock: day from 7 in the
     * morning to 7 in the evening.
     */
    fun isDay(here: LatLon?, epochMs: Long, zone: ZoneId = ZoneId.systemDefault()): Boolean {
        if (here != null) return sunElevation(here.lat, here.lon, epochMs) > horizon
        return Instant.ofEpochMilli(epochMs).atZone(zone).hour in 7..18
    }

    private fun mod(a: Double, b: Double) = ((a % b) + b) % b
}
