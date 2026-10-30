package com.commutescout.drive

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneOffset

/** Watch area math, labels, server JSON (old and new shapes) and request bodies. */
class WatchAreasTest {
    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private val palo = LatLon(37.442, -122.143)

    @Test fun radiusClampsAndLabels() {
        assertEquals(1, WatchGeo.clampRadius(0))
        assertEquals(25, WatchGeo.clampRadius(40))
        assertEquals("8 mi", WatchGeo.radiusLabel(8))
        assertEquals("25 mi, the most", WatchGeo.radiusLabel(25))
        // 25 mi is 40.23 km: the server's free limit is 40.2, so it is sent as the limit.
        assertEquals(40.2, WatchGeo.radiusKm(25), 1e-9)
        assertEquals(8 * 1.609344, WatchGeo.radiusKm(8), 1e-9)
        assertEquals(8, WatchGeo.radiusMi(12.87))
        assertEquals(25, WatchGeo.radiusMi(40.2))
    }

    @Test fun circleArea() {
        assertEquals(200, WatchGeo.circleSqMi(8))
        assertEquals(1960, WatchGeo.circleSqMi(25))
    }

    @Test fun dragMovesTheHandleThenZooms() {
        assertEquals(8, WatchGeo.radiusFromDrag(80f))
        assertEquals(12, WatchGeo.radiusFromDrag(120f))
        assertEquals(16, WatchGeo.radiusFromDrag(136f))
        assertEquals(25, WatchGeo.radiusFromDrag(1000f))
        assertEquals(1, WatchGeo.radiusFromDrag(0f))
        // On a wider screen the same miles take more dp.
        assertEquals(8, WatchGeo.radiusFromDrag(80f * 1.2f, 1.2f))
        assertEquals(120f, WatchGeo.handleDp(20), 1e-4f)
        assertEquals(80f, WatchGeo.handleDp(8), 1e-4f)
    }

    @Test fun zoomMathRoundTrips() {
        val z = WatchGeo.zoomForMpd(150.0, 37.4)
        assertEquals(150.0, WatchGeo.mpdAt(z, 37.4), 1e-6)
        // Twice the meters per dp is one zoom level out.
        assertEquals(z - 1, WatchGeo.zoomForMpd(300.0, 37.4), 1e-9)
        assertEquals(10.0, WatchGeo.zoomFor(11.0, 75.0, 150.0), 1e-9)
    }

    @Test fun polygonAreaMatchesTheServer() {
        // A 0.1 by 0.1 degree box at the equator: 11.132 by 11.057 km.
        val box = listOf(LatLon(0.0, 0.0), LatLon(0.0, 0.1), LatLon(0.1, 0.1), LatLon(0.1, 0.0))
        assertEquals(111.32 * 110.57 * 0.01 * Math.cos(Math.toRadians(0.05)), WatchGeo.polygonSqKm(box), 1e-6)
        assertEquals(0.0, WatchGeo.polygonSqKm(box.take(2)), 0.0)
        val start = WatchGeo.startPolygon(palo)
        assertEquals(5, start.size)
        assertTrue(WatchGeo.polygonSqMi(start) in 20..80)
        assertTrue(WatchGeo.polygonSqKm(start) < WatchGeo.FREE_POLYGON_SQ_KM)
    }

    @Test fun corridorAndRoutes() {
        val path = (0..1000).map { LatLon(37.0 + it * 0.001, -122.0) }
        val thin = WatchGeo.thin(path)
        assertTrue(thin.size <= 401)
        assertEquals(path.first(), thin.first()); assertEquals(path.last(), thin.last())
        assertEquals(111.2, WatchGeo.lengthKm(path), 0.5)
        assertEquals(2, WatchGeo.miles(WatchGeo.ROUTE_BUFFER_KM))
        assertTrue(WatchGeo.ROUTE_BUFFER_KM <= 3.2)
    }

    @Test fun circleRingIsClosedAndRound() {
        val ring = WatchGeo.circleRing(palo, 8 * WatchGeo.MI_M)
        assertEquals(ring.first().lat, ring.last().lat, 1e-9)
        ring.forEach { assertEquals(8 * 1.609344, WatchGeo.haversineKm(palo, it), 0.15) }
    }

    @Test fun watchJsonNewShape() {
        val w = json.decodeFromString<Watch>("""{"id":"a","name":"Work commute","type":"route","points":[{"lat":37.442,"lon":-122.143},{"lat":37.39,"lon":-122.03}],
            "buffer_km":3.2,"length_km":14.0,"kinds":["incident"],"active":true,"channels":{"push":true,"email":false},"quiet_hours":true,
            "live":{"count":2,"by_kind":{"incident":2},"top":{"kind":"incident","title":"Crash on US-101","body":""},"quiet_since":null},"extra":1}""")
        assertEquals("route", w.shape)
        assertEquals(2, w.path.size)
        assertEquals(LatLon(37.442, -122.143), w.path.first())
        val st = WatchText.status(w)!!
        assertEquals("2 alerts now", st.text); assertTrue(st.live)
        assertEquals("Your drive to Work, 2 mi each side", WatchText.meta(w, palo, LatLon(37.39, -122.03)))
        assertEquals("A 9 mi drive, 2 mi each side", WatchText.meta(w, null, null))
    }

    @Test fun watchJsonOldShape() {
        val w = json.decodeFromString<Watch>("""{"id":"b","type":"circle","center":{"lat":37.442,"lon":-122.143},"radius_km":12.87}""")
        assertEquals("circle", w.shape)
        assertNull(WatchText.status(w))   // an older server sends no live
        assertEquals("8 mi around Home", WatchText.meta(w, palo, null))
        assertEquals("8 mi around a point you chose", WatchText.meta(w, null, null))
        val old = json.decodeFromString<Watch>("""{"id":"c","type":"polygon","points":[[0,0],[0,0.1],[0.1,0.1],[0.1,0]]}""")
        assertEquals(4, old.path.size)
        val me = json.decodeFromString<MeResponse>("""{"email":"x","watches":[{"id":"d"}]}""")
        assertEquals(1, me.watches.size); assertNull(me.prefs)
    }

    @Test fun statusLines() {
        val quiet = Watch("q", live = Watch.Live(0, quiet_since = "2026-10-29T13:10:00Z"))
        assertEquals("Quiet since 1:10 PM", WatchText.status(quiet, ZoneOffset.UTC)!!.text)
        assertEquals("Quiet now", WatchText.status(Watch("q", live = Watch.Live(0)))!!.text)
        assertEquals("Paused", WatchText.status(Watch("p", active = false))!!.text)
        assertEquals("1 chain control now", WatchText.status(Watch("c", live = Watch.Live(1, top = Watch.Top("chain"))))!!.text)
        assertEquals("Chains required on I-70", WatchText.status(Watch("c", live = Watch.Live(1, top = Watch.Top("chain", "Chains required on I-70"))))!!.text)
    }

    @Test fun timesAndQuietLine() {
        assertEquals("10:00 PM", WatchText.time("22:00"))
        assertEquals("6:00 AM", WatchText.time("06:00"))
        assertEquals("10:00 PM to 6:00 AM, then one summary", WatchText.quietLine(QuietHours(true)))
        assertEquals("Off", WatchText.quietLine(null))
    }

    @Test fun createBodies() {
        val circle = json.parseToJsonElement(WatchBodies.create(WatchDraft("  ", "circle", palo, 25, kinds = setOf("fire", "incident")))).jsonObject
        assertEquals("Watch area", circle["name"]!!.jsonPrimitive.content)
        assertEquals("circle", circle["type"]!!.jsonPrimitive.content)
        assertEquals(40.2, circle["radius_km"]!!.jsonPrimitive.double, 1e-9)
        assertEquals(listOf("incident", "fire"), circle["kinds"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertTrue(circle["channels"]!!.jsonObject["push"]!!.jsonPrimitive.boolean)
        val route = json.parseToJsonElement(WatchBodies.create(WatchDraft("W", "route", points = listOf(palo, LatLon(37.39, -122.03))))).jsonObject
        assertEquals(3.2, route["buffer_km"]!!.jsonPrimitive.double, 1e-9)
        assertEquals(37.442, route["points"]!!.jsonArray[0].jsonArray[0].jsonPrimitive.double, 1e-9)
        val upd = json.parseToJsonElement(WatchBodies.update(WatchDraft("W", "circle", palo))).jsonObject
        assertFalse("center" in upd); assertFalse("points" in upd)
    }

    @Test fun prefsBodies() {
        assertEquals("""{"alerts_push":false}""", WatchBodies.prefs(push = false))
        val q = json.parseToJsonElement(WatchBodies.prefs(quiet = QuietHours(true, "23:00", "07:00", "America/Denver", false))).jsonObject["quiet_hours"]!!.jsonObject
        assertEquals("23:00", q["start"]!!.jsonPrimitive.content)
        assertEquals("America/Denver", q["tz"]!!.jsonPrimitive.content)
        assertFalse(q["summary"]!!.jsonPrimitive.boolean)
        assertEquals("""{"channels":{"push":true,"email":true}}""", WatchBodies.channels(true, true))
    }

    @Test fun areaDownloads() {
        val path = AreaMath.serpentine(37.35, -122.25, 37.55, -122.0)
        assertTrue(path.size > 4)
        assertTrue(path.all { it.lat in 37.35..37.55 && it.lon in -122.25..-122.0 })
        assertTrue(AreaMath.fits(37.35, -122.25, 37.55, -122.0))
        assertFalse(AreaMath.fits(34.0, -124.0, 40.0, -114.0))
        assertEquals("About 312 MB".length, AreaMath.aboutText(311_000_000).length)
        assertEquals("About 310 MB", AreaMath.aboutText(311_000_000))
        assertEquals("About 1.6 GB", AreaMath.aboutText(1_600_000_000))
        assertEquals("About 4 MB", AreaMath.aboutText(4_200_000))
        assertEquals(1_000_000L, AreaMath.estimateBytes(2.0, 2.0, 250_000.0))
        assertEquals(1_000_000L, AreaMath.estimateBytes(2.0, 2.0, null))
        assertNull(AreaMath.density(null, doubleArrayOf(0.0, 0.0, 1.0, 1.0)))
        assertEquals("22 by 16 mi", AreaMath.spanText(35.4, 25.75))
    }

    @Test fun storageSplit() {
        assertEquals(StorageSplit(0f, 0f, 0f), StorageSplit.of(0, 0, 0))
        val s = StorageSplit.of(3_000, 1_000, 0)
        assertEquals(0.75f, s.states, 1e-4f); assertEquals(0.25f, s.areas, 1e-4f); assertEquals(0f, s.trips, 0f)
        val tiny = StorageSplit.of(1_000_000, 0, 1)
        assertTrue(tiny.trips > 0.02f)
        assertEquals(1f, tiny.states + tiny.areas + tiny.trips, 1e-4f)
    }

    @Test fun savedWhenReadsLikeASentence() {
        val today = java.time.LocalDate.of(2026, 10, 29)
        fun at(d: Int, h: Int, m: Int) = java.time.LocalDateTime.of(2026, 10, d, h, m).toInstant(ZoneOffset.UTC).toEpochMilli()
        assertEquals("today, 6:40 AM", savedWhen(at(29, 6, 40), ZoneOffset.UTC, today))
        assertEquals("yesterday, 9:05 PM", savedWhen(at(28, 21, 5), ZoneOffset.UTC, today))
        assertEquals("Oct 12", savedWhen(at(12, 8, 0), ZoneOffset.UTC, today))
    }
}
