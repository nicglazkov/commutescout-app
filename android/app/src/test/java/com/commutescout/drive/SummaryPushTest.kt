package com.commutescout.drive

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SummaryPushTest {
    @Test fun summaryKindOpensWatchAreas() {
        assertTrue(AlertTap.opensWatchAreas(mapOf("event_kind" to "summary", "event_count" to "3")))
    }

    @Test fun watchPageLinkOpensWatchAreas() {
        assertTrue(AlertTap.opensWatchAreas(mapOf("url" to "https://example.com/watch")))
        assertTrue(AlertTap.opensWatchAreas(mapOf("csUrl" to "https://example.com/watch/")))
    }

    @Test fun anAlertWithASpotDoesNot() {
        assertFalse(AlertTap.opensWatchAreas(mapOf("url" to "https://example.com/watch?focus=37.442,-122.143&k=incident")))
        assertFalse(AlertTap.opensWatchAreas(mapOf("event_kind" to "incident", "url" to "https://example.com/?focus=37.442,-122.143")))
        assertFalse(AlertTap.opensWatchAreas(emptyMap()))
    }
}
