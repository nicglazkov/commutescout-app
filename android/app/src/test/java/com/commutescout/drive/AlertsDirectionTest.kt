package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Direction filtering: a northbound ramp closure must not be announced
 *  to a southbound driver. */
class AlertsDirectionTest {
    private fun marker(label: String, dir: String? = null) =
        RoadMarker(kind = "lane_closure", lat = 37.00, lon = -122.00, id = label, label = label, dir = dir)

    @Test fun headingFromLabelWords() {
        assertEquals(0.0, AlertsEngine.headingOf(marker("I-5 Off Ramp closed (northbound) @ Route 5")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("I-5 Off Ramp closed (southbound) @ Route 5")))
        assertEquals(90.0, AlertsEngine.headingOf(marker("SR-58 lane closure (eastbound)")))
        assertEquals(270.0, AlertsEngine.headingOf(marker("I-10 moving work zone (westbound) @ Route 15")))
    }

    @Test fun headingFromDirField() {
        assertEquals(0.0, AlertsEngine.headingOf(marker("Crash", dir = "NB")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("Crash", dir = "SB")))
        // What the server actually sends for LCS closures.
        assertEquals(0.0, AlertsEngine.headingOf(marker("I-5 lane closure , 1 of 4 lanes closed", dir = "North")))
        assertEquals(180.0, AlertsEngine.headingOf(marker("I-5 lane closure", dir = "South")))
        assertNull(AlertsEngine.headingOf(marker("I-5 lane closure", dir = "Both")))
    }

    @Test fun bothDirectionsOrNoneSaysNothing() {
        assertNull(AlertsEngine.headingOf(marker("I-5 lane closure , 1 of 4 lanes closed")))
        assertNull(AlertsEngine.headingOf(marker("I-5 closed northbound and southbound at the summit")))
    }

    @Test fun bearingAndAngle() {
        val south = AlertsEngine.bearing(LatLon(37.10, -122.00), LatLon(37.00, -122.00))
        assertEquals(180.0, south, 1.0)
        assertEquals(180.0, AlertsEngine.angleBetween(0.0, south), 1.0)     // northbound closure vs southbound driver: skipped
        assertEquals(0.0, AlertsEngine.angleBetween(180.0, south), 1.0)     // southbound closure: kept
        assertEquals(90.0, AlertsEngine.angleBetween(350.0, 80.0), 0.001)
    }
}
