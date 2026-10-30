package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** "Cleared" is said only for an event still ahead that vanished before the driver got there. */
class ClearedAheadTest {
    private fun up(id: String, along: Double, kind: String = "incident") =
        Upcoming(RoadMarker(kind = kind, lat = 37.442, lon = -122.143, id = id), along)

    @Test fun anEventAheadThatVanishesHasCleared() {
        val old = listOf(up("a", 2_000.0), up("b", 5_000.0))
        val new = listOf(up("b", 5_000.0))
        assertEquals(listOf("incident:a"), AlertsEngine.clearedAhead(old, new, along = 500.0).map { it.id })
    }

    @Test fun passingAnEventSaysNothing() {
        // The driver is past it (or right on it): it dropping off is not news.
        val old = listOf(up("a", 1_000.0))
        assertTrue(AlertsEngine.clearedAhead(old, emptyList(), along = 1_100.0).isEmpty())
        assertTrue(AlertsEngine.clearedAhead(old, emptyList(), along = 950.0).isEmpty())
    }

    @Test fun onlyTheNextFewMiles() {
        val old = listOf(up("far", 30_000.0))
        assertTrue(AlertsEngine.clearedAhead(old, emptyList(), along = 0.0).isEmpty())
    }

    @Test fun camerasAndSignsDoNotClear() {
        val old = listOf(up("cam", 2_000.0, "camera"), up("sign", 2_000.0, "sign"))
        assertTrue(AlertsEngine.clearedAhead(old, emptyList(), along = 0.0).isEmpty())
    }

    @Test fun nothingBeforeTheFirstAnswer() {
        assertTrue(AlertsEngine.clearedAhead(emptyList(), emptyList(), along = 0.0).isEmpty())
    }
}
