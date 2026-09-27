package com.commutescout.drive

import kotlinx.serialization.builtins.ListSerializer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.io.InterruptedIOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * What the app keeps and says without a signal: which saved road events
 * are still worth showing, which failures mean "no network", and the
 * queued report's saved form.
 */
class OfflineTest {
    private fun marker(kind: String) =
        Backend.json.decodeFromString(RoadMarker.serializer(), """{"kind":"$kind","lat":37.0,"lon":-122.0}""")

    private val now = 1_800_000_000_000L
    private val minute = 60_000L

    @Test fun nothingIsCutWhileTheDataIsFresh() {
        val all = listOf("plugin", "incident", "lane_closure").map(::marker)
        assertEquals(all, ShelfLife.prune(all, now - 10 * minute, now))
        assertEquals(all, ShelfLife.prune(all, null, now))
    }

    @Test fun aPoliceReportGoesBeforeARoadworkClosure() {
        val all = listOf("plugin", "incident", "chain_control", "lane_closure", "wildfire").map(::marker)
        val at45 = ShelfLife.prune(all, now - 45 * minute, now).map { it.kind }
        assertEquals(listOf("incident", "chain_control", "lane_closure", "wildfire"), at45)
        val at3h = ShelfLife.prune(all, now - 180 * minute, now).map { it.kind }
        assertEquals(listOf("chain_control", "lane_closure", "wildfire"), at3h)
        val at13h = ShelfLife.prune(all, now - 13 * 60 * minute, now).map { it.kind }
        assertEquals(listOf("wildfire"), at13h)
    }

    @Test fun noNetworkIsToldApartFromARefusal() {
        assertTrue(Connectivity.isOffline(UnknownHostException("commutescout.com")))
        assertTrue(Connectivity.isOffline(SocketTimeoutException()))
        assertTrue(Connectivity.isOffline(InterruptedIOException("timeout")))
        assertTrue(Connectivity.isOffline(IOException("wrapped", UnknownHostException())))
        assertFalse(Connectivity.isOffline(BackendError("HTTP 503", 503)))
        assertFalse(Connectivity.isOffline(InterruptedIOException("interrupted")))
        assertFalse(Connectivity.isOffline(null))
    }

    @Test fun aQueuedReportSurvivesTheTripToDisk() {
        val list = listOf(PendingReport("POLICE_VISIBLE", 37.5, -122.1, 90.0, "left shoulder", now),
                          PendingReport("HAZARD_ON_ROAD", 37.6, -122.2, null, "", now + minute))
        val text = Backend.json.encodeToString(ListSerializer(PendingReport.serializer()), list)
        assertEquals(list, Backend.json.decodeFromString(ListSerializer(PendingReport.serializer()), text))
    }
}
