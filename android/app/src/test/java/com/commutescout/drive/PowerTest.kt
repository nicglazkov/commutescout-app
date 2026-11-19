package com.commutescout.drive

import com.google.android.gms.location.Priority
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The battery rules (Power.kt, docs/battery.md). A change here should be a deliberate one. */
class PowerTest {
    @Test fun tripKeepsOneHighAccuracyFixASecond() {
        val s = Power.location(navigating = true, driving = true)
        assertEquals(Priority.PRIORITY_HIGH_ACCURACY, s.priority)
        assertEquals(1000L, s.intervalMs)
        assertTrue(s.minDistanceM <= 5f)
    }

    @Test fun standingStillAsksForLess() {
        val idle = Power.location(navigating = false, driving = false)
        val drive = Power.location(navigating = false, driving = true)
        assertTrue(idle.intervalMs > drive.intervalMs)
        assertTrue(idle.minDistanceM > drive.minDistanceM)
    }

    @Test fun silenceAtSpeedIsALostSignalSilenceAfterBrakingIsAStop() {
        assertTrue(Power.speedUnknownAfterSilence(25.0))
        assertTrue(!Power.speedUnknownAfterSilence(5.0))
        assertTrue(!Power.speedUnknownAfterSilence(-1.0))
    }

    @Test fun mapDrawsAtThirtyUnlessTouched() {
        assertEquals(30, Power.mapFps(touching = false))
        assertNull(Power.mapFps(touching = true))
    }

    @Test fun beatsAlignToTheClock() {
        val now = 1_800_000_017_000L
        val wait = Power.untilNextBeat(now)
        assertEquals(0L, (now + wait) % 60_000L)
        assertTrue(wait in 1..60_000L)
        // Two loops starting 20 s apart land on the same beat.
        assertEquals(now + wait, now + 20_000 + Power.untilNextBeat(now + 20_000))
        assertEquals(0L, (now + Power.untilNextBeat(now, 120_000)) % 120_000L)
    }

    @Test fun pluginCadenceRoundsUpOntoTheBeat() {
        assertEquals(60_000L, Power.pluginEveryMs(15))
        assertEquals(60_000L, Power.pluginEveryMs(60))
        assertEquals(120_000L, Power.pluginEveryMs(90))
    }

    @Test fun snapshotIsReadLessOftenOnTheMove() {
        assertTrue(Power.snapshotEveryMs(true) > Power.snapshotEveryMs(false))
    }
}
