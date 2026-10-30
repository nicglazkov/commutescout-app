package com.commutescout.drive

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.DG
import kotlinx.serialization.json.buildJsonObject
import org.maplibre.compose.expressions.dsl.const
import org.maplibre.compose.expressions.value.LineCap
import org.maplibre.compose.expressions.value.LineJoin
import org.maplibre.compose.layers.FillLayer
import org.maplibre.compose.util.MaplibreComposable
import org.maplibre.compose.layers.LineLayer
import org.maplibre.compose.sources.GeoJsonData
import org.maplibre.compose.sources.rememberGeoJsonSource
import org.maplibre.spatialk.geojson.Feature
import org.maplibre.spatialk.geojson.FeatureCollection
import org.maplibre.spatialk.geojson.LineString
import org.maplibre.spatialk.geojson.Polygon
import org.maplibre.spatialk.geojson.Position

/**
 * What a page draws on the main map while it is open: the watch area
 * being edited (a circle or a shape, filled) or a drive with its
 * corridor. The page sets it; DriveScreen's map content draws it
 * through [MapDrawingLayers]; closing the page clears it.
 */
object MapDrawing {
    /** A filled area, as one closed ring. */
    var area by mutableStateOf<List<LatLon>?>(null)
    /** A line with a band around it [bandDp] wide (a route's corridor at the current zoom). */
    var line by mutableStateOf<List<LatLon>?>(null)
    var bandDp by mutableStateOf(0f)
    /** True while a page draws on the map itself: the search row and map buttons step aside. */
    var cover by mutableStateOf(false)

    fun clear() { area = null; line = null; bandDp = 0f; cover = false }
}

private fun pos(p: LatLon) = Position(p.lon, p.lat)

/** The map content hook: draws [MapDrawing], nothing when it is empty. */
@Composable
@MaplibreComposable
fun MapDrawingLayers() {
    val blue = DG.low
    MapDrawing.area?.takeIf { it.size >= 3 }?.let { ring ->
        val closed = if (ring.first() == ring.last()) ring else ring + ring.first()
        val src = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
            Feature(geometry = Polygon(listOf(closed.map(::pos))), properties = buildJsonObject {}))))
        FillLayer(id = "cs-draw-fill", source = src, color = const(blue.copy(alpha = .13f)))
        LineLayer(id = "cs-draw-edge", source = src, color = const(blue), width = const(2.5.dp), join = const(LineJoin.Round))
    }
    MapDrawing.line?.takeIf { it.size >= 2 }?.let { path ->
        val src = rememberGeoJsonSource(GeoJsonData.Features(FeatureCollection(
            Feature(geometry = LineString(path.map(::pos)), properties = buildJsonObject {}))))
        val band = MapDrawing.bandDp.coerceAtLeast(8f)
        LineLayer(id = "cs-draw-band-edge", source = src, color = const(blue.copy(alpha = .5f)), width = const((band + 2.5f).dp),
            cap = const(LineCap.Round), join = const(LineJoin.Round))
        LineLayer(id = "cs-draw-band", source = src, color = const(Color(0xFFE4EDFB).copy(alpha = .78f)), width = const(band.dp),
            cap = const(LineCap.Round), join = const(LineJoin.Round))
        LineLayer(id = "cs-draw-line", source = src, color = const(blue), width = const(3.5.dp),
            cap = const(LineCap.Round), join = const(LineJoin.Round))
    }
}

/**
 * The small map drawings in list rows: a street grid and a freeway (or
 * terrain for a state), and the thing that matters on top, drawn from
 * the real geometry where there is one. Sizes follow the mockup's 68.
 */
enum class Mini { CIRCLE, ROUTE, SHAPE, AREA, STATE, TRIP }

@Composable
fun MiniMap(kind: Mini, modifier: Modifier = Modifier, size: Dp = 68.dp, radius: Dp = 17.dp, path: List<LatLon> = emptyList(),
            dot: Color? = null, dashed: Boolean = false) {
    val shape = RoundedCornerShape(radius)
    Box(modifier.size(size).clip(shape).background(Color(0xFFEEF2F6)).border(1.dp, DG.hair, shape)) {
        Canvas(Modifier.size(size)) {
            val s = this.size.width / 68f
            fun o(x: Float, y: Float) = Offset(x * s, y * s)
            val blue = DG.low
            if (kind == Mini.STATE) {
                drawPath(Path().apply { moveTo(-4 * s, 50 * s); cubicTo(10 * s, 40 * s, 20 * s, 46 * s, 30 * s, 38 * s); cubicTo(40 * s, 30 * s, 52 * s, 30 * s, 72 * s, 22 * s) },
                    Color(0xFFE2E8EF), style = Stroke(10 * s))
                drawPath(Path().apply { moveTo(6 * s, 60 * s); lineTo(14 * s, 48 * s); lineTo(20 * s, 55 * s); lineTo(27 * s, 44 * s); lineTo(36 * s, 60 * s) },
                    Color(0xFFCFD8E2), style = Stroke(1.6f * s, join = StrokeJoin.Round))
            } else {
                var x = 6f; while (x < 68f) { drawLine(Color.White, o(x, 0f), o(x, 68f), 2.4f * s); x += 13f }
                var y = 8f; while (y < 68f) { drawLine(Color.White, o(0f, y), o(68f, y), 2.4f * s); y += 12f }
                val fwy = Path().apply { moveTo(-4 * s, 60 * s); cubicTo(14 * s, 48 * s, 26 * s, 40 * s, 34 * s, 30 * s); cubicTo(42 * s, 20 * s, 52 * s, 10 * s, 72 * s, 2 * s) }
                drawPath(fwy, Color(0xFFCBD5E0), style = Stroke(5.5f * s, cap = StrokeCap.Round))
                drawPath(fwy, Color.White, style = Stroke(3.5f * s, cap = StrokeCap.Round))
            }
            val pts = fit(path, this.size)
            when (kind) {
                Mini.CIRCLE -> {
                    drawCircle(blue.copy(alpha = .14f), 21 * s, o(34f, 36f)); drawCircle(blue, 21 * s, o(34f, 36f), style = Stroke(1.8f * s))
                    drawCircle(Color.White, 4.8f * s, o(34f, 36f)); drawCircle(blue, 3.2f * s, o(34f, 36f))
                }
                Mini.ROUTE, Mini.TRIP -> {
                    val p = if (pts.size >= 2) line(pts) else Path().apply {
                        moveTo(18 * s, 60 * s); lineTo(18 * s, 46 * s); lineTo(12 * s, 42 * s); lineTo(12 * s, 34 * s)
                        cubicTo(20 * s, 30 * s, 30 * s, 28 * s, 36 * s, 26 * s); cubicTo(42 * s, 24 * s, 48 * s, 14 * s, 58 * s, 6 * s)
                    }
                    drawPath(p, blue.copy(alpha = .16f), style = Stroke(13 * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    drawPath(p, blue, style = Stroke(2.6f * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
                    if (dot != null) {
                        val at = if (pts.size >= 2) pts[pts.size / 2] else o(36f, 26f)
                        drawCircle(Color.White, 7.3f * s, at); drawCircle(dot, 5.5f * s, at)
                    }
                }
                Mini.SHAPE -> {
                    val p = if (pts.size >= 3) line(pts, close = true) else Path().apply {
                        moveTo(14 * s, 16 * s); lineTo(46 * s, 10 * s); lineTo(58 * s, 34 * s); lineTo(44 * s, 56 * s); lineTo(12 * s, 52 * s); close()
                    }
                    drawPath(p, blue.copy(alpha = .14f)); drawPath(p, blue, style = Stroke(1.8f * s, join = StrokeJoin.Round))
                }
                Mini.AREA -> rect(o(10f, 12f), Size(48 * s, 44 * s), 9 * s, blue, dashed)
                Mini.STATE -> rect(o(11f, 17f), Size(46 * s, 34 * s), 2 * s, blue, dashed)
            }
        }
    }
}

private fun DrawScope.rect(at: Offset, size: Size, r: Float, blue: Color, dashed: Boolean) {
    val cr = androidx.compose.ui.geometry.CornerRadius(r, r)
    drawRoundRect(blue.copy(alpha = if (dashed) .1f else .14f), at, size, cr)
    drawRoundRect(blue, at, size, cr, style = Stroke(1.8f * this.size.width / 68f,
        pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(3f * this.size.width / 68f, 2.5f * this.size.width / 68f)) else null))
}

private fun line(pts: List<Offset>, close: Boolean = false) = Path().apply {
    moveTo(pts[0].x, pts[0].y); pts.drop(1).forEach { lineTo(it.x, it.y) }; if (close) close()
}

/** Real geometry, scaled into the thumb with a margin, north up. */
private fun fit(path: List<LatLon>, size: Size): List<Offset> {
    if (path.size < 2) return emptyList()
    val s = path.minOf { it.lat }; val n = path.maxOf { it.lat }; val w = path.minOf { it.lon }; val e = path.maxOf { it.lon }
    val k = kotlin.math.cos(Math.toRadians((s + n) / 2))
    val spanX = ((e - w) * k).coerceAtLeast(1e-6); val spanY = (n - s).coerceAtLeast(1e-6)
    val box = size.width * 0.70f
    val scale = box / maxOf(spanX, spanY).toFloat()
    val ox = (size.width - (spanX * scale).toFloat()) / 2; val oy = (size.height - (spanY * scale).toFloat()) / 2
    return path.map { Offset(ox + ((it.lon - w) * k * scale).toFloat(), oy + ((n - it.lat) * scale).toFloat()) }
}
