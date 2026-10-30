package com.commutescout.drive

import com.commutescout.drive.design.AlertWords
import com.commutescout.drive.design.Looks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    // What is said, and when.

    @Test fun theVoiceSaysTheCapsulesWords() {
        val crash = RoadMarker(kind = "incident", lat = 37.442, lon = -122.143, id = "a", label = "Trfc Collision-No Inj")
        assertEquals("Crash ahead has cleared", AlertWords.clearedLine(AlertWords.shortTitle(crash, Looks.of(crash))))
        assertEquals("Crash ahead has cleared", AlertsEngine.clearedSentence(crash))
        val closure = RoadMarker(kind = "lane_closure", lat = 37.442, lon = -122.143, id = "b")
        assertEquals("Lane closure ahead has cleared", AlertsEngine.clearedSentence(closure))
    }

    private val on = Prefs.AlertRule(true, true, 1500.0, 0.0)

    @Test fun speaksOnlyOnATripWithTheAlertsRule() {
        assertTrue(AlertsEngine.speaksCleared(on, muted = false, freeDrive = false))
        assertFalse(AlertsEngine.speaksCleared(on, muted = true, freeDrive = false))
        assertFalse(AlertsEngine.speaksCleared(on, muted = false, freeDrive = true))
        assertFalse(AlertsEngine.speaksCleared(on.copy(speak = false), muted = false, freeDrive = false))
        assertFalse(AlertsEngine.speaksCleared(on.copy(enabled = false), muted = false, freeDrive = false))
    }

    @Test fun aPluginEventFollowsThePluginSpeechSetting() {
        val plugin = RoadMarker(kind = "plugin", lat = 37.442, lon = -122.143, id = "p", source = "Test plugin")
        fun rule(speakPlugins: Boolean) = AlertChips.apply(on, plugin, AlertDelivery.VOICE, emptySet(), emptySet(), speakPlugins)
        assertFalse(AlertsEngine.speaksCleared(rule(false), muted = false, freeDrive = false))
        assertTrue(AlertsEngine.speaksCleared(rule(true), muted = false, freeDrive = false))
    }

    @Test fun theSilentDeliverySaysNothing() {
        val m = RoadMarker(kind = "incident", lat = 37.442, lon = -122.143, id = "a")
        assertFalse(AlertsEngine.speaksCleared(AlertChips.apply(on, m, AlertDelivery.SILENT, emptySet(), emptySet(), false), muted = false, freeDrive = false))
    }
}
