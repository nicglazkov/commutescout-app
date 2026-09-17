package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Direction filtering found on a real drive: a northbound ramp closure
 *  must not be announced to a southbound driver. */
class AlertsDirectionTest {
    private fun marker(label: String, dir: String? = null) =
        RoadMarker(kind = "lane_closure", lat = 34.87, lon = -118.88, id = label, label = label, dir = dir)

    @Test fun headingFromLabelWords() {
        assertEquals(0.0, AlertsEngine.headingOf(marker("I-5 Off Ramp closed (northbound) @ Route 5 (Lebec)")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("I-5 Off Ramp closed (southbound) @ Route 5 (Lebec)")))
        assertEquals(90.0, AlertsEngine.headingOf(marker("SR-58 lane closure (eastbound)")))
        assertEquals(270.0, AlertsEngine.headingOf(marker("I-10 moving work zone (westbound) @ Route 15")))
    }

    @Test fun headingFromDirField() {
        assertEquals(0.0, AlertsEngine.headingOf(marker("Crash", dir = "NB")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("Crash", dir = "SB")))
        // What the server actually sends for LCS closures.
        assertEquals(0.0, AlertsEngine.headingOf(marker("I-5 lane closure (Lebec), 1 of 4 lanes closed", dir = "North")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("I-5 lane closure (Lebec)", dir = "South")))
        assertNull(AlertsEngine.headingOf(marker("I-5 lane closure", dir = "Both")))
    }

    @Test fun bothDirectionsOrNoneSaysNothing() {
        assertNull(AlertsEngine.headingOf(marker("I-5 lane closure (Lebec), 1 of 4 lanes closed")))
        assertNull(AlertsEngine.headingOf(marker("I-5 closed northbound and southbound at Grapevine")))
    }

    @Test fun bearingAndAngle() {
        val south = AlertsEngine.bearing(LatLon(34.90, -118.90), LatLon(34.80, -118.90))
        assertEquals(180.0, south, 1.0)
        assertEquals(180.0, AlertsEngine.angleBetween(0.0, south), 1.0)     // northbound closure vs southbound driver: skipped
        assertEquals(0.0, AlertsEngine.angleBetween(180.0, south), 1.0)     // southbound closure: kept
        assertEquals(90.0, AlertsEngine.angleBetween(350.0, 80.0), 0.001)
    }
}
