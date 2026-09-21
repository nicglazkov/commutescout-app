package com.commutescout.drive

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.decodeFromStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The four kinds the app used to lose on the way from the server, read
 * from the shapes production actually sends, and the snapshot reader
 * that has to keep up with a nationwide file.
 */
class MarkerKindsTest {
    private fun parse(json: String): RoadMarker = Backend.json.decodeFromString(RoadMarker.serializer(), json)

    @Test fun cameraCarriesItsStillAndStream() {
        val m = parse(
            """{"kind":"camera","lat":38.15654,"lon":-121.67937,"name":"Hwy 12 at Rio Vista Bridge East",
               "route":"SR-12","direction":"","near":"Rio Vista",
               "image":"https://example.test/cam.jpg","stream":"https://example.test/cam.m3u8"}"""
        )
        assertEquals("Hwy 12 at Rio Vista Bridge East", m.displayTitle)
        assertEquals("https://example.test/cam.jpg", m.image)
        assertEquals("https://example.test/cam.m3u8", m.stream)
        // An empty direction must not leave a trailing space on the road line.
        assertEquals("SR-12", m.roadLine)
        assertEquals(listOf("SR-12", "Rio Vista"), m.detailLines)
    }

    /**
     * Some agencies name a camera after the road it watches, and a sign
     * has no name but its road. Printing the road under a title that
     * already is the road says the same thing twice.
     */
    @Test fun theRoadIsNotRepeatedUnderATitleThatAlreadySaysIt() {
        val camera = parse("""{"kind":"camera","lat":41.76,"lon":-86.73,"name":"I-94 @ Wilson","route":"I-94 @ Wilson","near":"New Buffalo"}""")
        assertEquals("I-94 @ Wilson", camera.displayTitle)
        assertEquals(listOf("New Buffalo"), camera.detailLines)

        val sign = parse("""{"kind":"sign","lat":37.3,"lon":-121.9,"route":"I-880","direction":"South","near":"San Jose","message":"SLOW"}""")
        assertEquals("I-880 South", sign.displayTitle)
        assertEquals(listOf("San Jose"), sign.detailLines)
    }

    @Test fun signSplitsItsBoardAndKnowsWhenItIsBlank() {
        val showing = parse(
            """{"kind":"sign","lat":38.07,"lon":-121.73,"route":"SR-160","direction":"North","near":"Rio Vista",
               "message":"MINUTES TO: / HWY 12 7 / ISLETON 12","lines":["MINUTES TO:","HWY 12 7","ISLETON 12"]}"""
        )
        assertEquals(listOf("MINUTES TO:", "HWY 12 7", "ISLETON 12"), showing.signLines)
        assertEquals("SR-160 North", showing.displayTitle)

        val blank = parse("""{"kind":"sign","lat":39.77,"lon":-120.04,"route":"SR-70","message":"","lines":[],"blank":true}""")
        assertTrue(blank.signLines.isEmpty())
        assertEquals(true, blank.blank)
    }

    @Test fun signFallsBackToSplittingTheMessage() {
        val m = parse("""{"kind":"sign","lat":39.0,"lon":-120.0,"message":"CHAINS REQUIRED / BEYOND DONNER"}""")
        assertEquals(listOf("CHAINS REQUIRED", "BEYOND DONNER"), m.signLines)
    }

    @Test fun weatherStationReadsEveryFieldItSends() {
        val m = parse(
            """{"kind":"rwis","lat":39.2834,"lon":-120.70311,"station":"Hwy 80 at Blue Canyon","route":"I-80",
               "air_c":18.2,"pave_c":0.0,"wind":2.2,"gust":5.6,"vis_m":7500.0,"wind_dir":10.0,"rh":13.0,"precip":null}"""
        )
        assertEquals("Hwy 80 at Blue Canyon", m.displayTitle)
        assertEquals(18.2, m.air_c!!, 0.001)
        assertEquals(0.0, m.pave_c!!, 0.001)
        assertEquals(5.6, m.gust!!, 0.001)
        assertEquals(7500.0, m.vis_m!!, 0.001)
        assertNull(m.precip)
        assertEquals(listOf("I-80"), m.detailLines)
    }

    /**
     * Some stations report the wind direction in degrees and others as
     * a compass abbreviation, in the same file. Reading it as a number
     * threw on the first station that sent "N" and lost the whole
     * bundle with it.
     */
    @Test fun windDirectionArrivesAsDegreesOrAsCompassPoints() {
        assertEquals("N", parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":10.0}""").windFrom)
        assertEquals("ENE", parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":70}""").windFrom)
        assertEquals("N", parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":355.0}""").windFrom)
        assertEquals("SSW", parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":"SSW"}""").windFrom)
        assertEquals("NW", parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":"nw"}""").windFrom)
        assertNull(parse("""{"kind":"rwis","lat":37.0,"lon":-122.0,"wind_dir":"VRB"}""").windFrom)
        assertNull(parse("""{"kind":"rwis","lat":37.0,"lon":-122.0}""").windFrom)
    }

    @Test fun tollReadsItsPriceRangeAndEntries() {
        val m = parse(
            """{"kind":"toll","corridor":"I-680 SB","src":"511.org","lat":37.88,"lon":-122.05,"pricing":"live",
               "toll_type":"express","min":0.75,"max":2.25,"n":17,"name":"I-680 SB",
               "label":"I-680 SB express lane (optional) ${'$'}0.75-${'$'}2.25 now",
               "entries":[{"label":"Monument Blvd","pts":[[38.02,-122.10]],
                           "rows":[["Monument Blvd",0.75],["South Main St",1.5]]}]}"""
        )
        assertEquals("${'$'}0.75 to ${'$'}2.25", m.tollRange)
        // The list gets the one-line summary, the card the corridor,
        // because the card states the price on its own line.
        assertEquals("I-680 SB express lane (optional) ${'$'}0.75-${'$'}2.25 now", m.displayTitle)
        assertEquals("I-680 SB", m.cardTitle)
        assertEquals(1, m.entries!!.size)
        assertEquals(listOf("Monument Blvd" to 0.75, "South Main St" to 1.5), m.entries[0].prices)
        // The corridor repeats the name here, so the card does not say it twice.
        assertTrue(m.detailLines.isEmpty())
    }

    @Test fun aTollNamedApartFromItsCorridorSaysBoth() {
        val m = parse("""{"kind":"toll","lat":37.5,"lon":-122.2,"name":"SM-101 NB","corridor":"US 101 express lanes","min":1.0,"max":1.0}""")
        assertEquals(listOf("US 101 express lanes"), m.detailLines)
    }

    @Test fun aSinglePriceIsNotShownAsARange() {
        val m = parse(
            """{"kind":"toll","lat":37.8,"lon":-122.3,"name":"Bay Bridge","src":"BATA","pricing":"fixed",
               "toll_type":"required","as_of":"January 2026","min":8.5,"max":8.5,"n":1,
               "toll_dir":"westbound","toll_note":"toward San Francisco"}"""
        )
        assertEquals("${'$'}8.50", m.tollRange)
        assertTrue(m.detailLines.contains("Westbound, toward San Francisco"))
    }

    @Test fun burnFootprintKeepsItsLobesApart() {
        val ring = "[[41.0,-123.0],[41.1,-123.0],[41.1,-123.1],[41.0,-123.0]]"
        val many = parse("""{"kind":"wildfire","lat":41.0,"lon":-123.0,"name":"MP18","poly":[$ring,$ring]}""")
        assertEquals(2, many.perimeter.size)
        assertEquals(4, many.perimeter[0].size)
        assertEquals(LatLon(41.1, -123.1), many.perimeter[0][2])

        // The older shape is one ring, not a list of them.
        val one = parse("""{"kind":"wildfire","lat":41.0,"lon":-123.0,"name":"MP18","poly":$ring}""")
        assertEquals(1, one.perimeter.size)
        assertEquals(4, one.perimeter[0].size)

        val none = parse("""{"kind":"wildfire","lat":41.0,"lon":-123.0,"name":"MP18"}""")
        assertTrue(none.perimeter.isEmpty())
    }

    @Test fun closureAndTollGeometryReadAsLines() {
        val closure = parse("""{"kind":"lane_closure","lat":37.8,"lon":-122.3,"path":[[37.81,-122.35],[37.80,-122.36]]}""")
        assertEquals(listOf(LatLon(37.81, -122.35), LatLon(37.80, -122.36)), closure.stretch)

        val toll = parse("""{"kind":"toll","lat":37.8,"lon":-122.0,"segs":[[[38.0,-122.1],[38.1,-122.2]],[[37.9,-122.0]]]}""")
        // A segment of one point is not a line and is left out.
        assertEquals(1, toll.corridorLines.size)
        assertEquals(2, toll.corridorLines[0].size)
    }

    @Test fun aDotWithNoGeometryIsJustADot() {
        val m = parse("""{"kind":"lane_closure","lat":37.8,"lon":-122.3,"label":"I-80 lane closure"}""")
        assertTrue(m.stretch.isEmpty())
        assertTrue(m.corridorLines.isEmpty())
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Test fun theSnapshotReaderKeepsOnlyWhatIsNearby() {
        val body = """
            {"schema":1,"build":"2.103.0","published":"2026-09-21T10:10:21+00:00","degraded":false,
             "markers":[
               {"kind":"incident","lat":37.34,"lon":-121.89,"label":"Collision"},
               {"kind":"camera","lat":34.05,"lon":-118.24,"name":"Far away"},
               {"kind":"toll","lat":37.50,"lon":-122.00,"name":"Nearby toll","min":1.0,"max":1.0},
               {"kind":"sign","lat":68.12,"lon":-149.00,"message":"FAR NORTH"}
             ]}
        """.trimIndent()
        val near = Backend.json.decodeFromStream(
            NearbyMarkers(doubleArrayOf(35.0, -123.0, 39.0, -120.0)),
            body.byteInputStream(),
        )
        assertEquals(listOf("incident", "toll"), near.map { it.kind })
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Test fun theSnapshotReaderIgnoresFieldsItDoesNotKnow() {
        val body = """{"schema":2,"something_new":{"a":1},"markers":[{"kind":"rwis","lat":37.0,"lon":-122.0,"air_c":9.0,"future":7}]}"""
        val near = Backend.json.decodeFromStream(
            NearbyMarkers(doubleArrayOf(36.0, -123.0, 38.0, -121.0)),
            body.byteInputStream(),
        )
        assertEquals(1, near.size)
        assertEquals(9.0, near[0].air_c!!, 0.001)
    }

    @Test fun everyLayerTheWebsiteOffersHasADotAndAnIcon() {
        assertEquals(Prefs.layerKinds.map { it.key }.toSet(), MarkerIcons.kinds.toSet())
        for (kind in MarkerIcons.kinds) {
            assertFalse("$kind has no colour of its own", MarkerIcons.color(kind) == androidx.compose.ui.graphics.Color.Gray)
            assertTrue("$kind has no label", MarkerIcons.label(kind).isNotBlank())
        }
    }

    @Test fun layerDefaultsMatchTheWebsite() {
        assertEquals(setOf("toll", "camera"), Prefs.offByDefault)
        // The query names, which are not always the kind that comes back.
        val api = Prefs.layerKinds.associate { it.key to it.api }
        assertEquals("closure", api["lane_closure"])
        assertEquals("chain", api["chain_control"])
        assertEquals("fire", api["wildfire"])
        for (kind in listOf("toll", "camera", "sign", "rwis")) assertEquals(kind, api[kind])
        assertEquals(Prefs.layerKinds.map { it.api }.toSet(), LiveData.MAP_KINDS.split(",").toSet())
    }

    @Test fun theViewportIsNotAskedForTheHeavyKinds() {
        for (kind in listOf("camera", "sign", "rwis")) assertTrue(kind in Prefs.snapshotOnlyKinds)
        for (kind in listOf("incident", "lane_closure", "chain_control", "wildfire", "toll", "plugin")) {
            assertFalse(kind in Prefs.snapshotOnlyKinds)
        }
        // Roadside information is never announced on a drive.
        for (kind in Prefs.snapshotOnlyKinds) assertFalse(kind in LiveData.KINDS.split(","))
    }
}
