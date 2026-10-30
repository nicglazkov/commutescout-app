package com.commutescout.drive

import com.commutescout.drive.design.DrawKind
import com.commutescout.drive.design.Drawings
import com.commutescout.drive.design.Looks
import com.commutescout.drive.design.Tone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The lane_layout contract: decoded loosely, drawn honestly. */
class LaneLayoutTest {
    private fun marker(json: String): RoadMarker = Backend.json.decodeFromString(RoadMarker.serializer(), json)

    private val crash = """{"kind":"incident","lat":37.442,"lon":-122.143,"type":"Collision",
        "lane_layout":{"total":4,"lanes":[{"n":1,"type":"general","state":"open"},{"n":2,"type":"general","state":"open"},
        {"n":3,"type":"general","state":"open"},{"n":4,"type":"general","state":"closed"}],
        "shoulder":{"left":"open","right":"closed"},"target":3,"basis":"feed"}}"""

    @Test fun decodesTheContract() {
        val l = marker(crash).laneLayout!!
        assertEquals(4, l.total)
        assertEquals(listOf(4), l.closedLanes)
        assertEquals(true, l.shoulderLeft)
        assertEquals(false, l.shoulderRight)
        assertEquals(3, l.target)
        assertEquals("feed", l.basis)
        assertEquals(4 to 3, l.merge)
        assertEquals("Move one lane left.", l.advice)
        assertEquals("Right lane blocked", l.summary)
    }

    @Test fun missingOrNullMeansNoLayout() {
        assertNull(marker("""{"kind":"incident","lat":37.442,"lon":-122.143}""").laneLayout)
        assertNull(marker("""{"kind":"incident","lat":37.442,"lon":-122.143,"lane_layout":null}""").laneLayout)
    }

    @Test fun aBrokenLayoutDropsOnlyTheDrawing() {
        val m = marker("""{"kind":"incident","lat":37.442,"lon":-122.143,"label":"Crash","lane_layout":"four lanes"}""")
        assertEquals("Crash", m.label)
        assertNull(m.laneLayout)
        assertNull(marker("""{"kind":"incident","lat":1,"lon":2,"lane_layout":{"total":0,"lanes":[]}}""").laneLayout)
    }

    @Test fun lanesTheFeedLeftOutAreOpen() {
        val l = LaneLayout.from(Backend.json.parseToJsonElement("""{"total":3,"lanes":[{"n":3,"state":"closed"},{"n":9,"state":"closed"}],"target":2.0}"""))!!
        assertEquals(3, l.lanes.size)
        assertEquals(listOf(3), l.closedLanes)
        assertEquals(2, l.target)
        assertEquals("general", l.lanes[0].type)
    }

    @Test fun onlyShouldersClosedDrawsNoMergeArrow() {
        val l = LaneLayout.from(Backend.json.parseToJsonElement("""{"total":3,"lanes":[],"shoulder":{"right":"closed"},"target":3}"""))!!
        assertNull(l.merge)
        assertNull(l.advice)
        assertEquals("Right shoulder closed", l.summary)
        val spec = Drawings.forAlert(DrawKind.POLICE, l)
        val path = spec.path!!
        assertEquals(path.from, path.to)
        assertTrue(spec.blocks.isNotEmpty())
    }

    @Test fun noTargetMeansNoArrow() {
        val l = LaneLayout.from(Backend.json.parseToJsonElement("""{"total":4,"lanes":[{"n":4,"state":"closed"}],"target":null,"basis":"count_only"}"""))!!
        assertNull(l.merge)
        assertEquals("count_only", l.basis)
    }

    @Test fun summariesSayWhichSide() {
        fun s(closed: List<Int>, total: Int = 4) = LaneLayout(total, (1..total).map { LaneLayout.Lane(it, closed = it in closed) }).summary
        assertEquals("2 right lanes closed", s(listOf(3, 4)))
        assertEquals("Left lane blocked", s(listOf(1)))
        assertEquals("All lanes closed", s(listOf(1, 2, 3, 4)))
        assertEquals("Lane 2 of 4 blocked", s(listOf(2)))
        assertNull(s(emptyList()))
    }

    @Test fun drawingFollowsTheLayout() {
        val l = marker(crash).laneLayout
        val spec = Drawings.forAlert(DrawKind.CRASH, l)
        assertEquals(4, spec.n)
        // Lane 4 is u 3; the arrow runs from it to lane 3 (u 2).
        assertTrue(spec.blocks.any { it.l0 == 3f && it.l1 == 3f })
        assertEquals(3f, spec.path!!.from)
        assertEquals(2f, spec.path!!.to)
    }

    @Test fun withoutALayoutTheKindDrawingClaimsNoLane() {
        val spec = Drawings.forAlert(DrawKind.CRASH, null)
        assertTrue(spec.blocks.isEmpty())
        assertEquals(spec.path!!.from, spec.path!!.to)
        assertNotNull(spec.marks.firstOrNull())
    }

    @Test fun looksPerKind() {
        assertEquals(Tone.HIGH, Looks.of(marker(crash)).tone)
        assertEquals("crash", Looks.of(marker(crash)).icon)
        val police = RoadMarker(kind = "plugin", lat = 0.0, lon = 0.0, flare_kind = "POLICE_VISIBLE")
        assertTrue(Looks.of(police).community)
        assertEquals(DrawKind.POLICE, Looks.of(police).draw)
        assertEquals(DrawKind.FIRE, Looks.ofKind("wildfire").draw)
    }
}
