package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalTime

/** The Settings pages' pure parts: units, data source health, API use, alert chips and the first-run steps. */
class SettingsLogicTest {

    // MARK: units and region

    @Test fun matchMyPhoneFollowsThePhoneAndAPickOverridesIt() {
        assertTrue(UnitRules.miles(DistanceChoice.AUTO, phoneMiles = true))
        assertFalse(UnitRules.miles(DistanceChoice.AUTO, phoneMiles = false))
        assertFalse(UnitRules.miles(DistanceChoice.KM, phoneMiles = true))
        assertTrue(UnitRules.miles(DistanceChoice.MILES, phoneMiles = false))
        assertTrue(UnitRules.h24(ClockChoice.AUTO, phone24 = true))
        assertFalse(UnitRules.h24(ClockChoice.H12, phone24 = true))
        assertTrue(UnitRules.h24(ClockChoice.H24, phone24 = false))
        assertTrue(UnitRules.fahrenheit(TempChoice.AUTO, phoneF = true))
        assertFalse(UnitRules.fahrenheit(TempChoice.C, phoneF = true))
        assertTrue(UnitRules.fahrenheit(TempChoice.F, phoneF = false))
    }

    @Test fun regionsThatUseMilesAndFahrenheit() {
        assertTrue(UnitRules.regionMiles("US")); assertTrue(UnitRules.regionMiles("gb")); assertFalse(UnitRules.regionMiles("CA"))
        assertTrue(UnitRules.regionFahrenheit("US")); assertFalse(UnitRules.regionFahrenheit("GB")); assertFalse(UnitRules.regionFahrenheit("DE"))
    }

    @Test fun clockTemperatureAndSummaryCopy() {
        assertEquals("8:42 AM", UnitRules.clock(LocalTime.of(8, 42), h24 = false))
        assertEquals("08:42", UnitRules.clock(LocalTime.of(8, 42), h24 = true))
        assertEquals("17:05", UnitRules.clock(LocalTime.of(17, 5), h24 = true))
        assertEquals("31°F", UnitRules.temperature(-0.6, fahrenheit = true))
        assertEquals("−1°C", UnitRules.temperature(-0.6, fahrenheit = false))
        assertEquals("Miles, 12-hour", UnitRules.summary(miles = true, h24 = false))
        assertEquals("Kilometers, 24-hour", UnitRules.summary(miles = false, h24 = true))
        assertEquals("Miles, from your region", UnitRules.autoDistance(true))
        assertEquals("24-hour, from your phone", UnitRules.autoClock(true))
        assertEquals("Celsius, from your region", UnitRules.autoTemp(false))
    }

    @Test fun warningDistancesSnapToTheNearestStepInEitherUnit() {
        assertEquals(1, aheadIndex(1500.0, miles = true))   // an old 1.5 km pick reads as 1 mi
        assertEquals("2 mi", aheadLabel(3000.0, miles = true))
        assertEquals("800 m", aheadLabel(805.0, miles = false))
        assertEquals(listOf("0.5 mi", "1 mi", "2 mi"), aheadSteps(true).map { it.second })
    }

    // MARK: data sources

    private val now = Instant.parse("2026-10-29T15:41:00Z").toEpochMilli()

    private val current = """
        {"checked_at": "2026-10-29T15:41:00+00:00",
         "summary": {"fresh": 3, "stale": 1, "down": 1, "live": 1, "off": 1, "states": 51},
         "sources": [
           {"name": "Weather alerts", "agency": "National Weather Service", "state": "Nationwide", "ok": true, "status": "fresh", "age_s": 60, "group": "national", "state_code": null},
           {"name": "Traffic speeds", "agency": "Live road speeds", "state": "Nationwide", "status": "live", "group": "national"},
           {"name": "Caltrans CCTV", "agency": "Caltrans", "state": "California", "ok": true, "status": "fresh", "age_s": 30, "group": "state", "state_code": "CA"},
           {"name": "CHP incidents", "agency": "CHP incident logs", "state": "California", "ok": true, "status": "stale", "age_s": 1320, "group": "state", "state_code": "CA"},
           {"name": "COtrip", "agency": "Colorado DOT", "state": "Colorado", "ok": false, "status": "down", "as_of": "2026-10-29T14:58:00Z", "age_s": 2580, "group": "state", "state_code": "CO"},
           {"name": "511NY", "agency": "511NY", "state": "New York", "ok": true, "status": "fresh", "age_s": 120, "group": "state", "state_code": "NY"},
           {"name": "Old feed", "agency": "Retired", "state": "Texas", "enabled": false, "status": "off", "group": "state", "state_code": "TX"}
         ]}
    """.trimIndent()

    @Test fun summaryCountsComeFromTheServerAndLiveCountsAsFresh() {
        val r = SourcesHealth.parse(current, now)!!
        assertEquals(4, r.fresh)
        assertEquals(1, r.stale)
        assertEquals(1, r.down)
        assertEquals("All 50 states and DC", r.coverage)
        assertEquals("1 down", r.headline)
        assertEquals(FeedStatus.DOWN, r.worst)
    }

    @Test fun statesGroupTheirFeedsAndReadAsTheWorst() {
        val r = SourcesHealth.parse(current, now)!!
        assertEquals(listOf("Weather alerts", "Traffic speeds"), r.national.map { it.title })
        assertEquals(listOf("CA", "CO", "NY"), r.stateRows.map { it.code })   // the switched-off Texas feed is not listed
        val ca = r.stateRows.first { it.code == "CA" }
        assertEquals(FeedStatus.STALE, ca.status)
        assertEquals("Caltrans, CHP incident logs", ca.by)
        assertEquals("22 min ago", SourcesHealth.ageText(ca))
        val co = r.stateRows.first { it.code == "CO" }
        assertEquals("No reply since 7:58 AM", SourcesHealth.ageText(co) { "7:58 AM" })
        assertEquals("Live", SourcesHealth.ageText(r.national[1]))
    }

    /** An older server: no status, group, age or summary. The app works them out the way the server does. */
    @Test fun oldShapeIsWorkedOutOnThePhone() {
        val old = """
            {"sources": [
              {"name": "NWS", "agency": "National Weather Service", "state": "Nationwide", "ok": true, "as_of": "2026-10-29T15:40:00Z"},
              {"name": "Caltrans", "agency": "Caltrans", "state": "California", "ok": true, "as_of": "2026-10-29T13:00:00Z"},
              {"name": "WSDOT", "agency": "WSDOT", "state": "Washington", "ok": true, "stale": false, "as_of": "2026-10-29T15:40:00Z", "stale_after_s": 600},
              {"name": "FL511", "agency": "Florida 511", "state": "Florida", "ok": false},
              {"name": "On demand", "agency": "TxDOT", "state": "Texas"}
            ]}
        """.trimIndent()
        val r = SourcesHealth.parse(old, now)!!
        assertNull(r.checkedAtMs)
        assertEquals(listOf("US"), r.national.map { it.code })
        val byCode = r.stateRows.associateBy { it.code }
        assertEquals(FeedStatus.STALE, byCode.getValue("CA").status)   // older than the 90 minute default
        assertEquals(FeedStatus.FRESH, byCode.getValue("WA").status)
        assertEquals(FeedStatus.DOWN, byCode.getValue("FL").status)
        assertEquals(FeedStatus.LIVE, byCode.getValue("TX").status)
        assertEquals(4, r.states)
        assertEquals(3, r.fresh)   // NWS, WSDOT and the on-demand feed
        assertEquals("4 states", r.coverage)
        assertEquals("1 down", r.headline)
    }

    @Test fun notSourcesIsNull() {
        assertNull(SourcesHealth.parse("<html>", now))
        assertNull(SourcesHealth.parse("{\"detail\": \"nope\"}", now))
        assertEquals("All fresh", SourcesHealth.report(emptyList(), null).headline)
    }

    // MARK: API use

    @Test fun usageMeterReadsTheAccountsLimit() {
        val body = """
            {"keys": [{"id": "k1", "prefix": "cs_ab", "name": "Script", "tier": "free", "daily_limit": 2000, "revoked": false},
                      {"id": "k2", "prefix": "cs_cd", "name": "Old", "tier": "pro", "daily_limit": 10000, "revoked": true}],
             "max_active": 5, "tiers": {"free": 2000, "pro": 10000},
             "usage": {"day": "2026-10-29", "requests": 1284, "limit": 2000, "as_of": "2026-10-29T15:40:00Z"},
             "keyless_daily": 10000}
        """.trimIndent()
        val u = ApiUsage.parse(body)!!
        assertEquals("free", u.tier)   // the revoked pro key does not count
        assertEquals(1, u.activeKeys)
        assertEquals("1,284", u.usedText)
        assertEquals("of 2,000", u.limitText)
        assertEquals(0.642f, u.fraction, 0.001f)
        assertFalse(u.full)
        assertEquals("a day with your free key", u.tierText)
        assertEquals("1 key", u.keysText)
        assertEquals(10000, u.keylessDaily)
    }

    @Test fun proKeyAndNoUsageBlock() {
        val u = ApiUsage.parse("""{"keys": [{"id": "k", "tier": "pro", "daily_limit": 10000}], "tiers": {"free": 2000, "pro": 10000}}""")!!
        assertEquals("pro", u.tier)
        assertEquals(10000, u.limit)
        assertEquals(0, u.requests)
        assertEquals("a day with your pro key", u.tierText)
        val none = ApiUsage.parse("""{"keys": []}""")!!
        assertEquals(ApiUsage.FREE_DAILY, none.limit)
        assertEquals("None", none.keysText)
        assertEquals("a day with a free key", none.tierText)
        val over = ApiUsage(2500, 2000, "free", null, 1)
        assertTrue(over.full); assertEquals(1f, over.fraction)
        assertNull(ApiUsage.parse("{}"))
    }

    // MARK: alert chips

    private fun m(kind: String, type: String? = null, id: String? = null, flare: String? = null) =
        RoadMarker(kind = kind, lat = 37.442, lon = -122.143, type = type, id = id, flare_kind = flare)

    @Test fun officialKindsFallIntoTheirChipsAndTiers() {
        assertEquals("crash", AlertChips.keyOf(m("incident", "Traffic Collision")))
        assertEquals("closure", AlertChips.keyOf(m("lane_closure")))
        assertEquals("chain", AlertChips.keyOf(m("chain_control")))
        assertEquals("camera", AlertChips.keyOf(m("camera")))
        assertEquals("toll", AlertChips.keyOf(m("toll")))
        assertEquals("hazard", AlertChips.keyOf(m("incident", "Debris")))
        assertNull(AlertChips.keyOf(m("plugin", flare = "POLICE_VISIBLE")))
        assertEquals(0, AlertChips.tierOf("fire")); assertEquals(1, AlertChips.tierOf("ice")); assertEquals(2, AlertChips.tierOf("sign"))
        assertEquals(10, AlertChips.keys.size)
        assertEquals(setOf("camera", "toll"), AlertChips.offByDefault)
    }

    @Test fun chipsPluginsAndDeliveryShapeTheRule() {
        val base = Prefs.AlertRule(true, true, 1609.0, 0.0)
        val crash = m("incident", "Traffic Collision")
        val plugin = m("plugin", id = "wz-flare:1", flare = "POLICE_VISIBLE")
        // Voice: official alerts speak; plugin alerts chime unless asked to speak.
        AlertChips.apply(base, crash, AlertDelivery.VOICE, emptySet(), emptySet(), false).let { assertTrue(it.enabled && it.speak && !it.chime) }
        AlertChips.apply(base, plugin, AlertDelivery.VOICE, emptySet(), emptySet(), false).let { assertTrue(it.enabled && !it.speak && it.chime) }
        AlertChips.apply(base, plugin, AlertDelivery.VOICE, emptySet(), emptySet(), true).let { assertTrue(it.speak && !it.chime) }
        // Sound chimes for everything; Silent says and plays nothing, but the alert still shows.
        AlertChips.apply(base, crash, AlertDelivery.SOUND, emptySet(), emptySet(), true).let { assertTrue(it.enabled && !it.speak && it.chime) }
        AlertChips.apply(base, crash, AlertDelivery.SILENT, emptySet(), emptySet(), true).let { assertTrue(it.enabled && !it.speak && !it.chime) }
        // A chip or a plugin switched off stops the alert.
        assertFalse(AlertChips.apply(base, crash, AlertDelivery.VOICE, setOf("crash"), emptySet(), false).enabled)
        assertFalse(AlertChips.apply(base, plugin, AlertDelivery.VOICE, emptySet(), setOf("wz-flare"), false).enabled)
        assertTrue(AlertChips.apply(base, plugin, AlertDelivery.VOICE, setOf("police", "crash"), emptySet(), false).enabled)
        // A per-kind rule that does not speak stays quiet under Voice.
        AlertChips.apply(base.copy(speak = false), crash, AlertDelivery.VOICE, emptySet(), emptySet(), false).let { assertFalse(it.speak || it.chime) }
    }

    // MARK: first run

    @Test fun firstRunStepsInOrder() {
        val s = WelcomeSteps.steps
        assertEquals(3, s.size)
        assertEquals(listOf(WelcomeSteps.Ask.LOCATION, WelcomeSteps.Ask.NOTIFICATIONS, WelcomeSteps.Ask.SIGN_IN), s.map { it.ask })
        assertEquals("Know the road before you drive it", s[0].title)
        assertEquals("Allow while using", s[0].yes)
        assertEquals("Allow notifications", s[1].yes)
        assertEquals("Start driving", s[2].no)
        assertNull(s[2].askTitle)
        assertEquals("Step 2 of 3", WelcomeSteps.label(1))
        assertEquals(1, WelcomeSteps.next(0)); assertEquals(2, WelcomeSteps.next(1)); assertNull(WelcomeSteps.next(2))
        assertEquals(4, WelcomeSteps.perks.size)
        assertNotNull(s.firstOrNull { "US" in it.body })   // nationwide, never one state
    }
}
