package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class ClearedWatchTest {
    private val zone = ZoneId.of("America/Los_Angeles")
    private val now = 1_790_000_000_000L

    private fun push(extra: Map<String, String?> = emptyMap()) = AlertTap.parse(mapOf(
        "event_id" to "chp-1", "event_kind" to "incident", "event_lat" to "37.442", "event_lon" to "-122.143",
        "event_title" to "Crash on US-101", "event_body" to "Two vehicles, right lane blocked.",
        "event_watch" to "Home area", "event_sent_at" to ((now - 25 * 60_000) / 1000).toString(),
    ) + extra)!!

    @Test fun clearedPushReadsTheStatusAndTheLanes() {
        val lanes = """{"total":4,"lanes":[{"n":4,"type":"general","state":"closed"}],"target":3,"basis":"feed"}"""
        val a = push(mapOf("event_status" to "cleared", "event_lane_layout" to lanes))
        assertEquals("cleared", a.status)
        assertEquals(4, a.laneLayout?.total)
        assertEquals(listOf(4), a.laneLayout?.closedLanes)
    }

    @Test fun badLaneJsonIsIgnored() {
        val a = push(mapOf("event_lane_layout" to "{not json"))
        assertNull(a.laneLayout)
        assertNull(a.status)
    }

    @Test fun clearedPushWordsUseTheTitleAndTheSendTime() {
        val a = push(mapOf("event_status" to "cleared", "event_lane_layout" to """{"total":3}"""))
        val t = ClearedText.of(a, EventStatus(EventState.CLEARED), now, zone)
        assertEquals("The crash on US-101 is over", t.capsuleTitle)
        assertEquals("Cleared 25 min ago", t.capsuleSub)
        assertEquals("Crash on US-101", t.panelTitle)
        assertEquals("This crash has cleared", t.headline)
        assertEquals("Cleared 25 min ago. All lanes are open.", t.detail)
        // The clear's send time is not when the alert went out.
        assertEquals("What your alert said", t.saidHeader)
    }

    @Test fun anAlertFoundClearedKeepsItsOwnTime() {
        val a = push()
        val t = ClearedText.of(a, EventStatus(EventState.CLEARED, clearedAt = now - 10 * 60_000), now, zone)
        assertEquals("Cleared 10 min ago", t.capsuleSub)
        // No lanes known: the panel does not claim they are open.
        assertEquals("Cleared 10 min ago.", t.detail)
        assertTrue(t.saidHeader.startsWith("What your alert said at "))
    }

    @Test fun aTitleWithoutARoadFallsBackToTheKind() {
        val a = push(mapOf("event_title" to "Big pileup", "event_status" to "cleared"))
        val t = ClearedText.of(a, EventStatus(EventState.CLEARED), now, zone)
        assertEquals("The incident is over", t.capsuleTitle)
        assertEquals("This incident has cleared", t.headline)
    }

    @Test fun onlyAClearedAlertWithNoMarkerGetsTheClearedLayout() {
        val a = push()
        assertTrue(EventSheet(null, a, EventStatus(EventState.CLEARED)).isClearedAlert())
        assertTrue(!EventSheet(null, a, EventStatus(EventState.GONE)).isClearedAlert())
        assertTrue(!EventSheet(null, null, EventStatus(EventState.CLEARED)).isClearedAlert())
        assertNotNull(a.sentAt)
    }
}
