package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MarketTest {
    private val cams = FlareSource("osm-cameras", "Speed and red light cameras", trust = "official", tier = "approved")
    private val waze = FlareSource("wz-flare", "Waze relay", trust = "community", tier = "unreviewed", attribution = "Waze relay")
    private val verified = FlareSource("v", "Verified feed", trust = "verified", tier = "approved", attribution = "A city")
    private val mine = FlareSource("m", "My feed", base = "https://example.com", trust = "private", tier = "private")

    @Test fun officialIsOnlyTrustOfficial() {
        assertEquals(Market.Data.OFFICIAL, Market.data(cams))
        assertEquals(Market.Data.PLUGIN, Market.data(verified))
        assertEquals(Market.Data.PLUGIN, Market.data(waze))
        assertEquals(Market.Data.PLUGIN, Market.data(mine))
    }

    @Test fun filterSplitsTheCatalog() {
        val all = listOf(cams, waze, verified)
        assertEquals(all, Market.filter(all, Market.Filter.ALL))
        assertEquals(listOf(cams), Market.filter(all, Market.Filter.OFFICIAL))
        assertEquals(listOf(waze, verified), Market.filter(all, Market.Filter.PLUGIN))
        assertEquals("Official data", Market.Filter.OFFICIAL.label)
    }

    @Test fun countLine() {
        assertEquals("2 added, 4 more to try", Market.countLine(6, 2))
        assertEquals("All 3 added", Market.countLine(3, 3))
        assertEquals("4 to try", Market.countLine(4, 0))
        assertEquals("Nothing listed here yet", Market.countLine(0, 0))
    }

    @Test fun pausedStillCountsAsAdded() {
        assertTrue(Market.isAdded("a", emptySet(), emptySet()))
        assertFalse(Market.isAdded("a", setOf("a"), emptySet()))
        assertTrue(Market.isAdded("a", setOf("a"), setOf("a")))
    }

    @Test fun makerNeverRepeatsTheName() {
        assertEquals("By CommuteScout", Market.maker(cams))
        assertEquals("By its community", Market.maker(waze))
        assertEquals("By A city", Market.maker(verified))
        assertEquals("Added by you", Market.maker(mine))
    }

    @Test fun detailsCopy() {
        assertEquals("Its alerts are on your map", Market.showSub(true))
        assertEquals("Off for now. Nothing is shown or asked for.", Market.showSub(false))
        assertTrue(Market.inAlerts(cams).startsWith("Its alerts can be spoken"))
        assertTrue(Market.inAlerts(waze).startsWith("Not reviewed"))
        assertEquals("None", Market.alertsNow(0))
        assertEquals("1 alert", Market.alertsNow(1))
        assertEquals("1,207 alerts", Market.alertsNow(1207))
        assertEquals("Every 30 s", Market.every(30))
        assertEquals("Every 1 min", Market.every(60))
        assertEquals("Every 2 h", Market.every(7200))
        assertEquals("Data from A city. Verify an alert before you rely on it.", Market.footnote(verified))
        assertEquals("Verify an alert before you rely on it.", Market.footnote(cams))
    }

    @Test fun answeringStates() {
        val now = java.time.Instant.parse("2026-10-29T12:00:00Z").toEpochMilli()
        assertEquals("Yes, 2 min ago" to true, Market.answering(waze.copy(ok = true, lastOk = "2026-10-29T11:58:00Z"), now))
        assertEquals("No" to false, Market.answering(waze.copy(ok = false), now))
        val (text, good) = Market.answering(waze, now)
        assertEquals("Not asked yet", text); assertNull(good)
        assertEquals("just now", Market.ago("2026-10-29T11:59:30Z", now))
        assertEquals("3 h ago", Market.ago("2026-10-29T09:00:00Z", now))
        assertEquals("1 day ago", Market.ago("2026-10-28T11:00:00Z", now))
    }

    @Test fun usesAlwaysEndWithWhatItCannotHave() {
        val mediated = Market.uses(waze)
        assertTrue(mediated.first().title.contains("through CommuteScout"))
        assertFalse(mediated.last().allowed)
        assertTrue(Market.uses(mine).first().sub.contains("asks it directly"))
        val own = Market.uses(waze.copy(base = "https://x", ownSessionPath = "/s"))
        assertEquals("Your sign-in", own[1].title)
        assertTrue(Market.uses(waze.copy(acceptsReports = true)).any { it.title.startsWith("Reports") })
    }
}
