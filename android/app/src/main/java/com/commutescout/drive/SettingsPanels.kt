package com.commutescout.drive

import android.graphics.BitmapFactory
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.maplibre.compose.camera.CameraPosition
import org.maplibre.compose.camera.rememberCameraState
import org.maplibre.compose.expressions.dsl.const
import org.maplibre.compose.layers.FillLayer
import org.maplibre.compose.layers.LineLayer
import org.maplibre.compose.map.GestureOptions
import org.maplibre.compose.map.MapOptions
import org.maplibre.compose.map.MaplibreMap
import org.maplibre.compose.map.OrnamentOptions
import org.maplibre.compose.map.RenderOptions
import org.maplibre.compose.sources.GeoJsonData
import org.maplibre.compose.sources.rememberGeoJsonSource
import org.maplibre.compose.style.BaseStyle
import org.maplibre.spatialk.geojson.Feature
import org.maplibre.spatialk.geojson.FeatureCollection
import org.maplibre.spatialk.geojson.LineString
import org.maplibre.spatialk.geojson.Polygon
import org.maplibre.spatialk.geojson.Position
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs
import kotlin.math.ln

// Pieces of Settings that show a thing rather than name it: the base
// map as pictures with a live preview, and a saved map checked against
// the disk. The iPhone app has the same pages.

/** The map as it will look, around the driver, in the chosen style: no need to close Settings to see it. */
@Composable
fun BaseMapPreview(model: DriveViewModel, height: Int = 180) {
    val here by model.here.collectAsStateWithLifecycle()
    val center = here ?: model.viewCenter ?: LatLon(37.5, -121.9)
    val camera = rememberCameraState(firstPosition = CameraPosition(target = Position(center.lon, center.lat), zoom = 13.0))
    MaplibreMap(
        modifier = Modifier.fillMaxWidth().height(height.dp).clip(RoundedCornerShape(10.dp)).testTag("basemap-preview"),
        baseStyle = BaseStyle.Json(model.styleJson),
        cameraState = camera,
        // A TextureView: a SurfaceView draws nothing inside a sheet's window.
        options = MapOptions(renderOptions = RenderOptions(renderMode = RenderOptions.RenderMode.TextureView),
            gestureOptions = GestureOptions.AllDisabled, ornamentOptions = OrnamentOptions.AllDisabled),
    )
}

/** The base maps as cards: a picture of each, the way the website shows them. Tapping one applies it at once. */
@Composable
fun BaseMapCards(choice: Prefs.MapStyle, dark: Boolean, onPick: (Prefs.MapStyle) -> Unit) {
    val context = LocalContext.current
    val styles = Prefs.MapStyle.entries
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        styles.chunked(3).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { s ->
                    val picked = s == choice
                    val bitmap = remember(s, dark) {
                        runCatching { context.assets.open("thumbs/${s.flavor(dark)}.webp").use { BitmapFactory.decodeStream(it) } }.getOrNull()
                    }
                    Column(Modifier.weight(1f).clickable { onPick(s) }.testTag("basemap-${s.name.lowercase()}")) {
                        Box(Modifier.fillMaxWidth().aspectRatio(1.5f).clip(RoundedCornerShape(8.dp))
                            .border(BorderStroke(if (picked) 2.5.dp else 1.dp,
                                if (picked) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant), RoundedCornerShape(8.dp))) {
                            bitmap?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxWidth(), contentScale = ContentScale.Crop) }
                            if (picked) Icon(Icons.Default.CheckCircle, "Chosen", Modifier.align(Alignment.TopEnd).padding(6.dp),
                                tint = MaterialTheme.colorScheme.primary)
                        }
                        Text(s.label, Modifier.padding(top = 6.dp), style = MaterialTheme.typography.bodyMedium,
                            fontWeight = if (picked) FontWeight.SemiBold else FontWeight.Normal)
                    }
                }
                repeat(3 - pair.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * The first 127 bytes of a PMTiles file, read from the file itself:
 * what the file says it holds, as opposed to what the app wrote down
 * when it saved it.
 */
data class PMTilesHeader(val version: Int, val minZoom: Int, val maxZoom: Int,
                         val south: Double, val west: Double, val north: Double, val east: Double, val tileCount: Long) {
    companion object {
        fun read(file: File): PMTilesHeader? = runCatching {
            RandomAccessFile(file, "r").use { f ->
                val bytes = ByteArray(127)
                f.readFully(bytes)
                if (String(bytes, 0, 7, Charsets.US_ASCII) != "PMTiles") return null
                val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                PMTilesHeader(version = bytes[7].toInt(), minZoom = bytes[100].toInt(), maxZoom = bytes[101].toInt(),
                    west = b.getInt(102) / 1e7, south = b.getInt(106) / 1e7, east = b.getInt(110) / 1e7, north = b.getInt(114) / 1e7,
                    tileCount = b.getLong(72))
            }
        }.getOrNull()
    }
}

/** What the disk says about a saved map: a double check on the record the app kept. */
data class MapFileCheck(val exists: Boolean, val bytesOnDisk: Long, val header: PMTilesHeader?)

/** `37.2°N to 38.1°N, 122.6°W to 121.7°W`. */
fun areaText(s: Double, w: Double, n: Double, e: Double): String {
    fun lat(v: Double) = String.format("%.1f°%s", abs(v), if (v >= 0) "N" else "S")
    fun lon(v: Double) = String.format("%.1f°%s", abs(v), if (v >= 0) "E" else "W")
    return "${lat(s)} to ${lat(n)}, ${lon(w)} to ${lon(e)}"
}

/**
 * One saved map, checked against the disk: the record the app kept,
 * what the file system says, and what the file's own header says. A
 * map that is "saved" is only saved when all three agree.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedMapDetailSheet(model: DriveViewModel, file: MapFiles.LocalFile, onClose: () -> Unit) {
    var check by remember { mutableStateOf<MapFileCheck?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    // The ground the file really covers: a state's outline or a corridor's route; the box is the fallback.
    var outline by remember { mutableStateOf<List<List<Pair<Double, Double>>>?>(null) }
    val usingLocal by MapFiles.usingLocal.collectAsStateWithLifecycle()
    LaunchedEffect(file.id) {
        check = MapFiles.check(file)
        if (file.kind == "state") outline = MapFiles.stateOutline(file.name)
    }

    ModalBottomSheet(onDismissRequest = onClose, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), modifier = Modifier.testTag("saved-map-sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(file.name, style = MaterialTheme.typography.titleLarge)
            val span = maxOf(file.north - file.south, (file.east - file.west) * 0.6)
            val zoom = (ln(300.0 / span) / ln(2.0)).coerceIn(3.0, 12.0)
            val camera = rememberCameraState(firstPosition = CameraPosition(
                target = Position((file.west + file.east) / 2, (file.south + file.north) / 2), zoom = zoom))
            MaplibreMap(
                modifier = Modifier.fillMaxWidth().height(220.dp).clip(RoundedCornerShape(10.dp)),
                baseStyle = BaseStyle.Json(model.styleJson),
                cameraState = camera,
                // A TextureView: a SurfaceView draws nothing inside a sheet's window.
        options = MapOptions(renderOptions = RenderOptions(renderMode = RenderOptions.RenderMode.TextureView),
            gestureOptions = GestureOptions.AllDisabled, ornamentOptions = OrnamentOptions.AllDisabled),
            ) {
                val path = file.path
                if (file.kind == "corridor" && path != null && path.size > 1) {
                    // The road, drawn as wide as the buffer the file was cut with.
                    val road = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
                        Feature(geometry = LineString(path.map { Position(it[1], it[0]) }), properties = buildJsonObject { put("k", JsonPrimitive("road")) }))))
                    LineLayer(id = "cs-saved-buffer", source = road, color = const(Color(0x402E80F7)), width = const(22.dp))
                    LineLayer(id = "cs-saved-road", source = road, color = const(Color(0xFF2E80F7)), width = const(3.dp))
                } else {
                    val rings = outline ?: listOf(listOf(file.west to file.south, file.east to file.south, file.east to file.north, file.west to file.north, file.west to file.south))
                    val area = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(rings.map { r ->
                        Feature(geometry = Polygon(listOf(r.map { Position(it.first, it.second) })), properties = buildJsonObject { put("k", JsonPrimitive("area")) })
                    })))
                    FillLayer(id = "cs-saved-fill", source = area, color = const(Color(0x2E2E80F7)))
                    LineLayer(id = "cs-saved-edge", source = area, color = const(Color(0xFF2E80F7)), width = const(2.dp))
                }
            }
            Text(if (file.kind == "state") "The state inside its border, at every zoom. The file is cut to the outline, not to a box."
                 else if (file.path == null) "The road and a few miles either side of it." else "The road, and about a mile and a half either side of it.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

            Heading("Status")
            val c = check
            if (c == null) {
                Row(verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.width(18.dp).height(18.dp)); Spacer(Modifier.width(10.dp)); Text("Checking the file") }
            } else {
                Fact("File on disk") { Verdict(if (c.exists) "Present" else "Missing", c.exists, if (c.exists) Icons.Default.CheckCircle else Icons.Default.Error) }
                if (c.exists) {
                    Fact("Readable") {
                        Verdict(if (c.header != null) "Yes, a PMTiles ${c.header.version} file" else "No, the file is damaged",
                            c.header != null, if (c.header != null) Icons.Default.CheckCircle else Icons.Default.Warning)
                    }
                    Fact("Size on disk") { Text(Units.bytes(c.bytesOnDisk)) }
                    if (c.bytesOnDisk != file.bytes) Text("The app recorded ${file.sizeText} when it saved this file.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (usingLocal?.id == file.id) Text("The map is drawing from this file right now", style = MaterialTheme.typography.bodySmall)

            c?.header?.let { h ->
                Heading("What the file says")
                Fact("Zoom levels") { Text("${h.minZoom} to ${h.maxZoom}") }
                Fact("Tiles") { Text(String.format("%,d", h.tileCount)) }
                Fact("Covers") { Text(areaText(h.south, h.west, h.north, h.east), style = MaterialTheme.typography.bodySmall) }
                Text("Read from the file's own header, not from the app's notes about it.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            Heading("Record")
            Fact("Kind") { Text(if (file.kind == "state") "Whole state" else "Trip corridor") }
            Fact("Saved") { Text(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(file.savedAt))) }
            file.build?.let { Fact("Map build") { Text(it) } }
            Fact("Covers") { Text(areaText(file.south, file.west, file.north, file.east), style = MaterialTheme.typography.bodySmall) }
            Fact("File") { Text(MapFiles.path(file).name, style = MaterialTheme.typography.bodySmall) }

            Spacer(Modifier.height(4.dp))
            Button({ confirmDelete = true }, Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.errorContainer, contentColor = MaterialTheme.colorScheme.onErrorContainer)) {
                Text("Delete this map")
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false },
        title = { Text("Delete ${file.name}?") },
        text = { Text("Without it the map needs a signal here.") },
        confirmButton = { TextButton({ confirmDelete = false; MapFiles.delete(file); onClose() }) { Text("Delete") } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Cancel") } })
}

@Composable
private fun Fact(label: String, value: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        value()
    }
}

@Composable
private fun Verdict(text: String, good: Boolean, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    val tint = if (good) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.width(18.dp).height(18.dp), tint = tint)
        Spacer(Modifier.width(6.dp))
        Text(text, color = tint)
    }
}

