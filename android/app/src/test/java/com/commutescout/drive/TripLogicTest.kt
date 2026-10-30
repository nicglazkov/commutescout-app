package com.commutescout.drive

import com.commutescout.drive.ReportSteps.Step
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class TripLogicTest {
    private val pacific = ZoneId.of("America/Los_Angeles")
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private val sample = """
        {"checked_at":"2026-10-29T15:30Z","departures":[
          {"depart_at":"2026-10-29T15:30Z","now":true,"drive_min":32,"delay_min":10},
          {"depart_at":"2026-10-29T15:40Z","now":false,"drive_min":28,"delay_min":6},
          {"depart_at":"2026-10-29T15:50Z","now":false,"drive_min":24,"delay_min":2},
          {"depart_at":"2026-10-29T16:00Z","now":false,"drive_min":null,"delay_min":null}],
         "best":{"depart_at":"2026-10-29T15:50Z","drive_min":24,"saving_min":8},
         "reason":"Traffic should ease by then"}
    """.trimIndent()

    @Test fun boldPrefixMatchesStartIgnoringCase() {
        assertEquals(4, TripText.boldPrefix("Palo Alto", "palo"))
        assertEquals(4, TripText.boldPrefix("Palo Alto", "  Palo "))
        assertEquals(0, TripText.boldPrefix("Palo Alto", "alto"))
        assertEquals(0, TripText.boldPrefix("Palo Alto", ""))
        assertEquals(0, TripText.boldPrefix("Pa", "Palo"))
    }

    @Test fun boundNamesTheCompassDirection() {
        assertEquals("northbound", TripText.bound(10.0))
        assertEquals("eastbound", TripText.bound(80.0))
        assertEquals("southbound", TripText.bound(181.0))
        assertEquals("westbound", TripText.bound(290.0))
        assertEquals("northbound", TripText.bound(350.0))
        assertNull(TripText.bound(null))
        assertNull(TripText.bound(-1.0))
    }

    @Test fun routesLabel() {
        assertEquals("Routes", TripText.routesLabel(null))
        assertEquals("1 route", TripText.routesLabel(1))
        assertEquals("3 routes", TripText.routesLabel(3))
    }

    @Test fun leaveLaterParsesAndPicksTheBest() {
        val a = json.decodeFromString<LeaveLaterAnswer>(sample)
        assertTrue(LeaveLater.usable(a))
        assertEquals("Leave at 8:50 to save 8 min", LeaveLater.title(a, pacific))
        val bars = LeaveLater.bars(a, pacific)
        assertEquals(3, bars.size) // the unknown slot has no bar
        assertEquals("Now", bars[0].label)
        assertTrue(bars[0].now)
        assertEquals("8:40", bars[1].label)
        assertEquals(listOf(false, false, true), bars.map { it.best })
        assertEquals(1f, bars[0].height, 1e-4f)   // slowest
        assertEquals(.25f, bars[2].height, 1e-4f) // quickest
        assertTrue(bars[1].height in .25f..1f)
        assertEquals("15:50", LeaveLater.clock("2026-10-29T15:50Z", ZoneId.of("UTC"), h24 = true))
    }

    @Test fun leaveLaterEqualBarsAndNoBest() {
        val a = LeaveLaterAnswer(departures = listOf(LeaveDeparture("2026-10-29T15:30Z", true, 20), LeaveDeparture("2026-10-29T15:40Z", false, 20)),
            reason = "Leaving now is as quick as any time in the next hour")
        assertEquals("Leave now", LeaveLater.title(a, pacific))
        assertTrue(LeaveLater.bars(a, pacific).all { it.height == .6f && !it.best })
    }

    @Test fun leaveLaterHidesOnMissingFields() {
        assertFalse(LeaveLater.usable(null))
        assertFalse(LeaveLater.usable(LeaveLaterAnswer()))
        // Leaving now unknown.
        assertFalse(LeaveLater.usable(LeaveLaterAnswer(departures = listOf(LeaveDeparture("x", true, null), LeaveDeparture("y", false, 20), LeaveDeparture("z", false, 22)))))
        // Only one known time.
        assertFalse(LeaveLater.usable(LeaveLaterAnswer(departures = listOf(LeaveDeparture("x", true, 20)))))
        assertNull(LeaveLater.clock("not a time"))
    }

    @Test fun reportStepsUndoAndSendOnce() {
        var s: Step = Step.Grid
        assertEquals(Step.Grid, ReportSteps.send(s)) // nothing picked, nothing sent
        s = ReportSteps.pick("crash")
        assertEquals(Step.Confirm("crash"), s)
        assertEquals(Step.Grid, ReportSteps.undo(s))
        s = ReportSteps.send(s)
        assertEquals(Step.Sending("crash"), s)
        assertEquals(s, ReportSteps.send(s))  // a second tap does not send again
        assertEquals(s, ReportSteps.undo(s))  // too late to undo
        val failed = ReportSteps.failed(s, "No")
        assertEquals(Step.Failed("crash", "No"), failed)
        assertEquals(Step.Sending("crash"), ReportSteps.send(failed)) // try again
        assertEquals(Step.Sent("crash"), ReportSteps.sent(s))
        assertEquals(Step.Grid, ReportSteps.sent(Step.Grid))
    }

    @Test fun reportUndoCountdown() {
        assertEquals(5, ReportSteps.secondsLeft(0f))
        assertEquals(5, ReportSteps.secondsLeft(.1f))
        assertEquals(3, ReportSteps.secondsLeft(.5f))
        assertEquals(1, ReportSteps.secondsLeft(.99f))
        assertEquals(0, ReportSteps.secondsLeft(1f))
    }

    @Test fun reportKindsMapToFlare() {
        assertEquals(12, ReportKinds.all.size)
        val accepted = setOf("POLICE_VISIBLE", "CRASH_MAJOR", "JAM_HEAVY", "HAZARD_OBJECT", "HAZARD_SHOULDER_CAR", "ROAD_CLOSED",
            "LANE_CLOSED", "WEATHER_ICE", "WEATHER_FOG", "WEATHER_FLOOD", "CHAINS_REQUIRED", "MAP_ISSUE")
        assertEquals(accepted, ReportKinds.all.map { it.flare }.toSet())
        assertEquals("crash", ReportKinds.byFlare("CRASH_MAJOR")?.id)
        val police = ReportKinds.byFlare("POLICE_VISIBLE")!!
        val crash = ReportKinds.byFlare("CRASH_MAJOR")!!
        val fog = ReportKinds.byFlare("WEATHER_FOG")!!
        assertEquals(2, ReportKinds.defaultWhere(police))
        assertEquals(1, ReportKinds.defaultWhere(crash))
        assertEquals("Shoulder. Two cars", ReportKinds.description(police, 2, " Two cars "))
        assertEquals("Left lane.", ReportKinds.description(crash, 0, ""))
        assertEquals("Thick", ReportKinds.description(fog, 0, "Thick"))
        assertEquals("Report a crash here, southbound", ReportKinds.confirmTitle(crash, "southbound"))
        assertEquals("Report fog here", ReportKinds.confirmTitle(fog, null))
    }

    @Test fun arriveStatsAndAvoided() {
        val place = Place(name = "Palo Alto, CA", lat = 37.442, lon = -122.143, kind = PlaceKind.recent)
        val crash = RoadMarker(kind = "incident", lat = 37.4, lon = -122.1, id = "a")
        val camera = RoadMarker(kind = "camera", lat = 37.4, lon = -122.1, id = "b")
        val r = TripRecord(place, startedAt = 0L, meters = 29_934.0, warned = listOf(crash, camera, crash), arrivedAt = 26 * 60_000L)
        val s = ArriveStats.of(r, now = 99_999_999L, miles = true) { "8:44 AM" }
        assertEquals("26 min", s.driveTime)
        assertEquals("18 mi", s.distance)
        assertEquals("8:44 AM", s.arrived)
        assertEquals(listOf(crash), ArriveStats.avoided(r))
        // Still under way: the clock runs to now, at least a minute.
        assertEquals("1 min", ArriveStats.of(r.copy(arrivedAt = null), now = 1000L, miles = true) { "" }.driveTime)
    }

    @Test fun onTheWayKeepsMarkersOnTheLineInOrder() {
        val line = (0..100).map { LatLon(37.0 + it * .001, -122.0) } // dense, like a real route
        val far = RoadMarker(kind = "incident", lat = 37.08, lon = -122.0, id = "far")
        val near = RoadMarker(kind = "incident", lat = 37.02, lon = -122.0, id = "near")
        val off = RoadMarker(kind = "incident", lat = 37.05, lon = -121.98, id = "off")
        val camera = RoadMarker(kind = "camera", lat = 37.05, lon = -122.0, id = "cam")
        assertEquals(listOf("near", "far"), OnTheWay.along(line, listOf(far, off, camera, near)).map { it.marker.id })
        assertTrue(OnTheWay.along(listOf(LatLon(37.0, -122.0)), listOf(near)).isEmpty())
    }

    @Test fun theDriveLineNeverWaitsForever() {
        assertEquals("Checking the drive", TripText.driveStatus(asked = false, located = true))
        assertEquals("Waiting for your location", TripText.driveStatus(asked = false, located = false))
        assertEquals("Drive time is not available right now", TripText.driveStatus(asked = true, located = true))
    }
}
