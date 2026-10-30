package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The event sheet's pure parts: a tapped alert read from its push, what
 * became of it, and the web map's wording ported word for word.
 */
class EventsTest {
    private fun parse(json: String): RoadMarker = Backend.json.decodeFromString(RoadMarker.serializer(), json)
    private val la: ZoneId = ZoneId.of("America/Los_Angeles")
    private val ny: ZoneId = ZoneId.of("America/New_York")
    /** A fixed now: Thursday 29 October 2026, 10:00 AM in Palo Alto. */
    private val now = ZonedDateTime.of(2026, 10, 29, 10, 0, 0, 0, la).toInstant().toEpochMilli()
    private fun epoch(day: Int, hour: Int, minute: Int = 0, zone: ZoneId = la) =
        ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toEpochSecond()

    @Test fun watchKindsMapToMarkerKinds() {
        assertEquals("incident", EventKinds.markerKind("incident"))
        assertEquals("lane_closure", EventKinds.markerKind("closure"))
        assertEquals("chain_control", EventKinds.markerKind("chain"))
        assertEquals("wildfire", EventKinds.markerKind("fire"))
        // The map's own words pass through.
        assertEquals("lane_closure", EventKinds.markerKind("lane_closure"))
        assertNull(EventKinds.markerKind("camera"))
        assertEquals("closure", EventKinds.noun("lane_closure"))
        assertEquals("chain control", EventKinds.noun("chain_control"))
    }

    @Test fun aNewPushCarriesTheEvent() {
        val a = AlertTap.parse(mapOf(
            "url" to "https://commutescout.com/?focus=37.44200,-122.14300&k=closure",
            "event_id" to "lcs:123", "event_kind" to "closure", "event_lat" to "37.442", "event_lon" to "-122.143",
            "event_title" to "Lane closure on US-101", "event_body" to "Right lane closed.",
            "event_watch" to "Home area", "event_sent_at" to "1793289600",
        ))!!
        assertEquals("lcs:123", a.eventId)
        assertEquals("lane_closure", a.kind)
        assertEquals(37.442, a.lat, 1e-9)
        assertEquals(-122.143, a.lon, 1e-9)
        assertEquals("Home area", a.watch)
        assertEquals(1793289600L, a.sentAt)
    }

    @Test fun anOldPushHasOnlyItsLink() {
        val a = AlertTap.parse(mapOf("csUrl" to "https://commutescout.com/?focus=37.442,-122.143&k=fire"))!!
        assertNull(a.eventId)
        assertEquals("wildfire", a.kind)
        assertEquals(37.442, a.lat, 1e-9)
        assertNull(a.title)
        // No place, no alert: an ordinary launch.
        assertNull(AlertTap.parse(mapOf("url" to "https://commutescout.com/map")))
        assertNull(AlertTap.parse(emptyMap()))
    }

    private val alert = AlertTap("chp:ABC", "incident", 37.442, -122.143, "Crash on US-101", "Two cars.", "Home area", now / 1000 - 25 * 60)
    private val near = parse("""{"kind":"incident","lat":37.4425,"lon":-122.1432,"id":"XYZ","type":"1183-Trfc Collision-Unkn Inj"}""")
    private val same = parse("""{"kind":"incident","lat":37.446,"lon":-122.143,"id":"ABC","type":"1183-Trfc Collision-Unkn Inj"}""")

    @Test fun theChpIdWinsOverTheNearest() {
        assertEquals("ABC", EventResolve.nearest(listOf(near, same), alert)?.id)
        assertEquals("XYZ", EventResolve.nearest(listOf(near), alert)?.id)
        val far = near.copy(lat = 37.46)
        assertNull(EventResolve.nearest(listOf(far), alert))
        // Another kind at the spot is not it.
        assertNull(EventResolve.nearest(listOf(near.copy(kind = "wildfire")), alert))
    }

    @Test fun statusFromTheServer() {
        val active = EventStatusAnswer(state = "active", marker = same, checked_at = "2026-10-29T17:00:00+00:00")
        val (m, s) = EventResolve.resolve(alert, active, emptyList(), now)
        assertEquals("ABC", m?.id)
        assertEquals(EventState.ACTIVE, s.state)
        assertFalse(s.unconfirmed)

        val cleared = EventStatusAnswer(state = "cleared", cleared_at = "2026-10-29T16:50:00+00:00", nearby = near)
        val (cm, cs) = EventResolve.resolve(alert, cleared, listOf(same), now)
        // Never borrows the map's marker for a cleared event.
        assertNull(cm)
        assertEquals(EventState.CLEARED, cs.state)
        assertEquals("XYZ", cs.nearby?.id)

        val changed = EventStatusAnswer(state = "changed", event = AlertedEvent(title = "R-2 on I-80"), marker = same)
        assertEquals("R-2 on I-80", EventResolve.resolve(alert, changed, emptyList(), now).second.newTitle)
        assertEquals(EventState.GONE, EventResolve.resolve(alert, EventStatusAnswer(state = "gone"), listOf(same), now).second.state)
    }

    @Test fun withoutTheServerTheMapDecides() {
        val (m, s) = EventResolve.resolve(alert, null, listOf(near), now)
        assertEquals("XYZ", m?.id)
        assertEquals(EventState.ACTIVE, s.state)
        assertTrue(s.unconfirmed)
        val (none, unknown) = EventResolve.resolve(alert, null, emptyList(), now)
        assertNull(none)
        assertEquals(EventState.UNKNOWN, unknown.state)
    }

    @Test fun bannerCopy() {
        val active = EventBanner.text(EventStatus(EventState.ACTIVE), alert, "incident", now, la)
        assertEquals("Still active", active.headline)
        assertEquals("Checked just now. Alert sent 25 min ago.", active.detail)
        val cleared = EventBanner.text(EventStatus(EventState.CLEARED, clearedAt = now - 10 * 60_000), alert, "lane_closure", now, la)
        assertEquals("Cleared 10 min ago", cleared.headline)
        assertEquals("This closure is no longer reported. Your alert from 9:35 AM is below.", cleared.detail)
        val gone = EventBanner.text(EventStatus(EventState.GONE), alert, "incident", now, la)
        assertEquals("It ended or the agency stopped reporting it. Your alert from 9:35 AM is below.", gone.detail)
        val changed = EventBanner.text(EventStatus(EventState.CHANGED, newTitle = "R-2 on I-80"), alert.copy(title = "R-1 on I-80"), "chain_control", now, la)
        assertEquals("Now: R-2 on I-80. Your alert said: R-1 on I-80.", changed.detail)
        val unknown = EventBanner.text(EventStatus(EventState.UNKNOWN), alert, "incident", now, la)
        assertEquals("Couldn't check the status", unknown.headline)
        assertTrue(unknown.retry)
        assertEquals("Checking the latest status", EventBanner.text(EventStatus(EventState.LOADING), alert, null, now, la).headline)
    }

    @Test fun agoReadsLikeTheWebsite() {
        assertEquals("just now", EventText.agoMs(now - 20_000, now))
        assertEquals("12 min ago", EventText.agoMs(now - 12 * 60_000, now))
        assertEquals("1 hour ago", EventText.agoMs(now - 70 * 60_000, now))
        assertEquals("3 days ago", EventText.agoMs(now - 3 * 86_400_000L, now))
    }

    @Test fun scheduleWithAnEndAhead() {
        val m = parse("""{"kind":"lane_closure","lat":37.442,"lon":-122.143,"cls":"lane","since":${epoch(29, 7)},"until":${epoch(29, 21)}}""")
        val s = EventText.schedule(m, now, la)
        assertEquals("Scheduled to end tonight at 9:00 PM PDT (your timezone)", s.head)
        assertEquals("That is about 11 hours from now. It started today at 7:00 AM.", s.tail)
        assertTrue(s.zoneLines.isEmpty())
    }

    @Test fun schedulePastItsEnd() {
        val m = parse("""{"kind":"lane_closure","lat":37.442,"lon":-122.143,"cls":"full-roadway","until":${epoch(29, 9, 20)}}""")
        val s = EventText.schedule(m, now, la)
        assertEquals("Was scheduled to end today at 9:20 AM PDT (your timezone)", s.head)
        assertEquals("That was 40 minutes ago. The state transportation agency has not reported it open. Assume the road is still closed.", s.tail)
    }

    @Test fun scheduleWithNoEndAndAnotherViewerZone() {
        val m = parse("""{"kind":"lane_closure","lat":37.442,"lon":-122.143,"cls":"lane","src":"WSDOT","since":${epoch(28, 22)}}""")
        val s = EventText.schedule(m, now, ny)
        assertEquals("No scheduled end", s.head)
        assertEquals("The restriction stays until WSDOT reports it clear. It started yesterday at 10:00 PM.", s.tail)
        assertEquals(listOf("In your timezone:", "Start: Thursday, Oct 29 at 1:00 AM EDT"), s.zoneLines)
    }

    @Test fun whenPhraseDays() {
        assertEquals("tomorrow at 6:00 AM", EventText.whenPhrase(epoch(30, 6), la, 0, now, la))
        assertEquals("Monday at 6:00 AM", EventText.whenPhrase(ZonedDateTime.of(2026, 11, 2, 6, 0, 0, 0, la).toEpochSecond(), la, 0, now, la))
        assertEquals("Friday, Nov 20 at 6:00 AM", EventText.whenPhrase(ZonedDateTime.of(2026, 11, 20, 6, 0, 0, 0, la).toEpochSecond(), la, 0, now, la))
    }

    @Test fun shapeShoutTurnsShoutingIntoSentences() {
        assertEquals("Closed due to rockslide. Use SR-1 detour.", EventText.shapeShout("CLOSED DUE TO ROCKSLIDE//USE SR1 DETOUR"))
        assertEquals("Right lane closed for paving.", EventText.shapeShout("RIGHT LANE CLOSED FOR PAVING"))
        // Mixed case is left as written.
        assertEquals("Right lane closed on I-80", EventText.shapeShout("Right lane closed on I-80"))
        assertEquals("Traffic on US-50 stopped.", EventText.shapeShout("TRAFFIC ON US50 STOPPED"))
    }

    @Test fun humanizeAndSplitRoad() {
        assertEquals("Lane closure", EventText.humanize("LANE_CLOSURE"))
        // Mixed case keeps its inner capitals, as on the website.
        assertEquals("Road Work", EventText.humanize("roadWork"))
        assertNull(EventText.humanize(""))
        assertEquals("US 89" to "Emergency Maintenance, NB State St", EventText.splitRoad("US 89: Emergency Maintenance, NB State St"))
        assertEquals(null to "Crash near the ramp", EventText.splitRoad("Crash near the ramp"))
    }

    @Test fun chpGlossDecodesTheCode() {
        assertEquals("Collision reported, details still coming in. CHP has the call but no injury assessment yet.",
            EventText.chpGloss("1183-Trfc Collision-Unkn Inj"))
        assertEquals("A traffic signal is defective. Treat the intersection as an all-way stop.", EventText.chpGloss("1166-Defective Traffic Signals"))
        assertEquals("A live or struck animal on the road. Expect brief slowing.", EventText.chpGloss("Live or Dead Animal"))
        assertNull(EventText.chpGloss("Assist CT with Maintenance"))
    }

    @Test fun chainLegendLeadsWithTheLevelNow() {
        val p = EventText.chainPanel("R2")
        assertEquals("Caltrans reports R-2 here", p.head)
        assertEquals("Chains required on every vehicle, except 4WD/AWD with snow tires on all four wheels. Even those must carry chains.", p.text)
        assertEquals(listOf("R-1", "R-3"), p.legend.map { it.first })
        val none = EventText.chainPanel("Lifted")
        assertNull(none.head)
        assertEquals(3, none.legend.size)
    }

    @Test fun incidentCardMatchesTheWebPopup() {
        val m = parse("""{"kind":"incident","lat":37.442,"lon":-122.143,"id":"260729PA0001","type":"1183-Trfc Collision-Unkn Inj",
            "label":"US101 N: Crash at University Ave","location":"US101 N at University Ave","dir":"N","area":"Palo Alto",
            "reported":"2026-10-29T16:48:00+00:00","log_n":4}""")
        val c = EventCard.of(m, now, la, miles = true)
        assertEquals("Incident", c.chip)
        assertEquals("12 min ago", c.age)
        assertEquals("1183 trfc collision unkn inj", c.title.lowercase())
        assertEquals("US101 N at University Ave", c.subtitle)
        assertEquals(listOf("Direction" to "Affects the N side"), c.facts)
        assertEquals(listOf("Reported 12 min ago", "Source: CHP Palo Alto dispatch"), c.footer)
        assertEquals(4, c.dispatchCount)
    }

    @Test fun closureCardMatchesTheWebPopup() {
        val m = parse("""{"kind":"lane_closure","lat":37.442,"lon":-122.143,"cls":"full-roadway","route":"US-101","county":"Test",
            "dir":"Northbound","lanes":"2 lanes","work":"PAVING","delay_min":10,"windows":3,"until":${epoch(29, 21)}}""")
        val c = EventCard.of(m, now, la, miles = true)
        assertEquals("Road closed", c.chip)
        assertTrue(c.darker)
        assertEquals("US-101, Test", c.title)
        assertEquals("All lanes closed", c.warning)
        assertEquals(listOf("Work" to "Paving", "Delay" to "~10 min expected", "Windows" to "2 more scheduled at this spot"), c.facts)
        assertEquals(listOf("Source: State transportation agency lane closures"), c.footer)
        assertEquals("Lanes closed", EventCard.closureChip("lane"))
        assertEquals("One-way traffic", EventCard.closureChip("one-way-traffic"))
    }

    @Test fun wildfireAndPassRestrictionCards() {
        val fire = EventCard.of(parse("""{"kind":"wildfire","lat":37.442,"lon":-122.143,"name":"Ridge","acres":1250.4,"contained":40}"""), now, la, true)
        assertEquals("Ridge Fire", fire.title)
        assertEquals(listOf("Size" to "1,250 acres", "Contained" to "40% contained"), fire.facts)
        assertEquals("No mapped perimeter yet. The dot marks the reported origin.", fire.gloss)
        val pass = EventCard.of(parse("""{"kind":"chain_control","lat":37.442,"lon":-122.143,"src":"WSDOT","route":"Test Pass",
            "label":"Traction tires advised; Traction tires advised; Oversize vehicles prohibited"}"""), now, la, true)
        assertEquals("Pass restriction", pass.chip)
        assertEquals(listOf("Traction tires advised. Oversize vehicles prohibited."), pass.body)
        assertEquals(listOf("Source: WSDOT mountain pass reports"), pass.footer)
    }

    @Test fun unitLinesTellOneStoryEach() {
        val u = DispatchUnit(1, listOf(UnitStep("assigned", "12:39 AM"), UnitStep("en route", "12:40 AM")), done = false)
        assertEquals("Unit 1: assigned 12:39 AM, en route 12:40 AM. Still working the scene", EventText.unitLine(u, 0))
        assertEquals("Unit 2: assigned 12:39 AM, cleared to leave 1:05 AM",
            EventText.unitLine(DispatchUnit(null, listOf(UnitStep("assigned", "12:39 AM"), UnitStep("cleared to leave", "1:05 AM")), true), 1))
    }

    @Test fun newFieldsDecodeAndOddNumbersDoNotBreakTheMarker() {
        val m = parse("""{"kind":"plugin","lat":37.442,"lon":-122.143,"source":"Flare","flare_kind":"CAMERA_SPEED","label":"Speed camera, 35 mph zone",
            "confirmations":2.0,"reliability":0.83,"road":"El Camino Real","ttl_s":3600,"source_url":"https://example.test/a","tier":"approved"}""")
        val c = EventCard.of(m, now, la, true)
        assertEquals("Speed camera", c.title)
        assertEquals("35 mph zone", c.subtitle)
        assertEquals(listOf("Road" to "El Camino Real", "Confirmed" to "2 times", "Reliability" to "83%"), c.facts)
        assertEquals(listOf("Source: Flare (approved by CommuteScout)"), c.footer)
        assertEquals("https://example.test/a", c.link)
    }

    @Test fun theCameraCentresSouthOfTheEvent() {
        // At zoom 14 near Palo Alto a dp is about 3.8 m; 0.22 of an 800 dp screen is 176 dp.
        val mpp = EventCamera.metersPerDp(37.442, 14.0)
        assertEquals(3.79, mpp, 0.01)
        val centre = EventCamera.centerLat(37.442, 14.0, 800.0)
        assertEquals(37.442 - 176 * mpp / 111_320.0, centre, 1e-9)
        assertTrue(centre < 37.442)
    }
}
