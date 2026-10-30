package com.commutescout.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.AlertRow
import com.commutescout.drive.design.AlertWords
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Looks
import com.commutescout.drive.design.Note
import com.commutescout.drive.design.Tone
import com.commutescout.drive.design.glass
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/*
 * Debug builds only: scenes for screenshots and for checking the design
 * by eye. Each is reached with an intent extra (MainActivity). Test
 * coordinates are the public Palo Alto ones; nothing here is real data.
 */
object DebugScenes {
    /** How long a cleared event stays in the slot; debug scenes hold it for a screenshot. */
    var clearedHoldMs = 3200L

    private fun layout(json: String): JsonElement = Json.parseToJsonElement(json)

    /** A sample marker of each kind the design draws, at [at]. */
    fun sample(kind: String, at: LatLon): RoadMarker = when (kind) {
        "closure" -> RoadMarker(kind = "lane_closure", lat = at.lat, lon = at.lon, id = "debug-closure", route = "I-280 N", label = "Lane closure",
            lanes = "2 right lanes closed", detail = "Pavement repair. Use the left lanes.", since = System.currentTimeMillis() / 1000 - 3 * 3600,
            lane_layout = layout("""{"total":4,"lanes":[{"n":1,"state":"open"},{"n":2,"state":"open"},{"n":3,"state":"closed"},{"n":4,"state":"closed"}],"target":2,"basis":"feed"}"""))
        "hazard" -> RoadMarker(kind = "plugin", lat = at.lat, lon = at.lon, id = "wz-flare:debug-hazard", source = "Community", flare_kind = "HAZARD_ON_ROAD_OBJECT",
            description = "Object on road", road = "US-101 S", reported = isoAgo(4), confirmations = 6.0,
            lane_layout = layout("""{"total":4,"lanes":[{"n":1,"state":"closed"},{"n":2,"state":"open"},{"n":3,"state":"open"},{"n":4,"state":"open"}],"target":2,"basis":"feed"}"""))
        "police" -> RoadMarker(kind = "plugin", lat = at.lat, lon = at.lon, id = "wz-flare:debug-police", source = "Community", flare_kind = "POLICE_VISIBLE",
            description = "Police reported", road = "US-101 S", reported = isoAgo(9))
        "jam" -> RoadMarker(kind = "plugin", lat = at.lat, lon = at.lon, id = "wz-flare:debug-jam", source = "Community", flare_kind = "JAM_HEAVY_TRAFFIC",
            description = "Slow traffic", road = "US-101 S", reported = isoAgo(2))
        "chain" -> RoadMarker(kind = "chain_control", lat = at.lat, lon = at.lon, id = "debug-chain", status = "R-2", route = "I-80 E", location = "Kingvale")
        "fire" -> RoadMarker(kind = "wildfire", lat = at.lat, lon = at.lon, id = "debug-fire", name = "Oak", acres = 1240.0, contained = 35.0)
        "ice" -> RoadMarker(kind = "rwis", lat = at.lat, lon = at.lon, id = "debug-ice", station = "Summit Rd", route = "SR-17 S", pave_c = -0.5, air_c = 1.0, surface = "Icy")
        "sign" -> RoadMarker(kind = "sign", lat = at.lat, lon = at.lon, id = "debug-sign", route = "US-101", direction = "S", near = "Whipple Ave",
            lines = listOf("SAN JOSE   24 MIN", "SFO   18 MIN"))
        "camera" -> RoadMarker(kind = "plugin", lat = at.lat, lon = at.lon, id = "osm-cameras:debug-camera", source = "Cameras", flare_kind = "CAMERA_SPEED",
            description = "Speed camera", road = "El Camino Real")
        "toll" -> RoadMarker(kind = "toll", lat = at.lat, lon = at.lon, id = "debug-toll", name = "US-101 express lanes", corridor = "US-101 S express lanes", min = 4.5)
        else -> RoadMarker(kind = "incident", lat = at.lat, lon = at.lon, id = "debug-crash", type = "Collision", label = "Crash", route = "US-101 S",
            location = "University Ave", detail = "Two vehicles, right lane blocked. CHP is on scene.", reported = isoAgo(12),
            lane_layout = layout("""{"total":4,"lanes":[{"n":1,"state":"open"},{"n":2,"state":"open"},{"n":3,"state":"open"},{"n":4,"state":"closed"}],"shoulder":{"right":"open"},"target":3,"basis":"feed"}"""))
    }

    private fun isoAgo(min: Int): String = java.time.Instant.now().minusSeconds(min * 60L).toString()

    /**
     * Once a trip is running, puts a [kind] event [gapMeters] ahead on
     * the route; with [clearAfterMs], takes it away again as a clear.
     */
    fun forceAhead(kind: String, gapMeters: Double = 1290.0, clearAfterMs: Long? = null) {
        CoroutineScope(Dispatchers.Main).launch {
            var tries = 0
            while ((Engine.alerts.stretchAhead().isEmpty()) && tries++ < 120) delay(500)
            delay(1500)
            val up = Engine.alerts.forceOnRoute(gapMeters) { sample(kind, it) }
            android.util.Log.i("DebugScenes", "forced $kind: ${up?.id}")
            if (up == null) return@launch
            clearAfterMs?.let { delay(it); Engine.alerts.forceClear(up) }
        }
    }

    val CATALOG = listOf("crash", "closure", "chain", "fire", "hazard", "jam", "ice", "police", "sign", "camera", "toll")

    /** Every alert kind in the design's catalog, grouped as it groups them. */
    @Composable
    fun Catalog() {
        val here = LatLon(37.442, -122.143)
        val rows = CATALOG.mapIndexed { i, k -> sample(k, here).let { m -> AlertWords.of(m, 400.0 + i * 900.0, 26.0) to m } }
        Box(Modifier.fillMaxSize().safeDrawingPadding().padding(10.dp).testTag("debug-catalog")) {
            Column(Modifier.fillMaxWidth().glass(RoundedCornerShape(28.dp), strong = true).verticalScroll(rememberScrollState()).padding(vertical = 10.dp)) {
                Looks.GROUPS.forEachIndexed { g, name ->
                    Text(name, style = DGType.label, color = DG.sub, modifier = Modifier.padding(start = 16.dp, top = if (g == 0) 4.dp else 14.dp, bottom = 2.dp))
                    rows.filter { it.first.look.group == g }.forEach { (w, m) ->
                        AlertRow(w, m, mono = if (m.kind == "sign") m.lines?.joinToString("  ") else null)
                    }
                }
            }
        }
    }

    /** Every app message, as the design lists them. */
    @Composable
    fun System() {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = DG.gutter, vertical = 10.dp).verticalScroll(rememberScrollState()).testTag("debug-system"),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Note("reroute", Tone.LOW, "Rerouting", "Finding a new route from here.")
            Note("confirm", Tone.MID, "Is the object still there?", "Reported 4 min ago, just behind you", action = "Still there", onAction = {}, secondary = "Gone", onSecondary = {})
            Note("speed", Tone.HIGH, "Over the limit", "72 in a 65")
            Note("gps", Tone.CLEAR, "GPS signal lost", "Following the route from your last position")
            Note("offline", Tone.CLEAR, "No connection", "Guidance continues. Alerts as of 8:14 AM.")
            Note("watch", Tone.GOOD, "Home area: crash on US-101", "Tapped from a notification. Cleared 25 min ago.", action = "Show on map", onAction = {})
            Note("arrive", Tone.GOOD, "You have arrived", "Palo Alto, CA", action = "Done", onAction = {}, inline = true)
            Box(Modifier.height(1.dp).background(DG.hair))
        }
    }
}
