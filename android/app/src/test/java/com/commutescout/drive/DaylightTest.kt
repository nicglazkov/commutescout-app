package com.commutescout.drive

import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DaylightTest {
    private fun ms(y: Int, mo: Int, d: Int, h: Int, mi: Int, zone: String) =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, ZoneId.of(zone)).toInstant().toEpochMilli()

    private val sf = LatLon(37.7749, -122.4194)
    private val london = LatLon(51.5074, -0.1278)

    @Test fun noonIsDayAndMidnightIsNight() {
        assertTrue(Daylight.isDay(sf, ms(2026, 6, 21, 12, 0, "America/Los_Angeles")))
        assertFalse(Daylight.isDay(sf, ms(2026, 6, 21, 0, 0, "America/Los_Angeles")))
        assertTrue(Daylight.isDay(london, ms(2026, 12, 21, 12, 0, "Europe/London")))
        assertFalse(Daylight.isDay(london, ms(2026, 12, 21, 18, 0, "Europe/London")))
    }

    @Test fun itTurnsAtSunsetForThePlace() {
        // San Francisco, 21 June 2026: sunset is about 8:35 in the evening.
        assertTrue(Daylight.isDay(sf, ms(2026, 6, 21, 20, 20, "America/Los_Angeles")))
        assertFalse(Daylight.isDay(sf, ms(2026, 6, 21, 20, 50, "America/Los_Angeles")))
        // And 21 December: sunrise about 7:21, sunset about 4:55.
        assertFalse(Daylight.isDay(sf, ms(2026, 12, 21, 7, 5, "America/Los_Angeles")))
        assertTrue(Daylight.isDay(sf, ms(2026, 12, 21, 7, 40, "America/Los_Angeles")))
        assertTrue(Daylight.isDay(sf, ms(2026, 12, 21, 16, 40, "America/Los_Angeles")))
        assertFalse(Daylight.isDay(sf, ms(2026, 12, 21, 17, 10, "America/Los_Angeles")))
    }

    @Test fun theSunIsHighestNearLocalNoon() {
        // Summer solstice at San Francisco: about 75.7 degrees up at solar noon (1:11 in the afternoon).
        assertEquals(75.7, Daylight.sunElevation(sf.lat, sf.lon, ms(2026, 6, 21, 13, 11, "America/Los_Angeles")), 0.5)
    }

    @Test fun withoutAPositionItGoesByTheClock() {
        val zone = ZoneId.of("America/Chicago")
        assertTrue(Daylight.isDay(null, ms(2026, 3, 3, 7, 0, "America/Chicago"), zone))
        assertTrue(Daylight.isDay(null, ms(2026, 3, 3, 18, 59, "America/Chicago"), zone))
        assertFalse(Daylight.isDay(null, ms(2026, 3, 3, 19, 0, "America/Chicago"), zone))
        assertFalse(Daylight.isDay(null, ms(2026, 3, 3, 6, 59, "America/Chicago"), zone))
    }
}
