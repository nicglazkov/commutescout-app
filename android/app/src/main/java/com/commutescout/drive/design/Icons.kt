package com.commutescout.drive.design

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The design's one icon set: every alert kind and every control, drawn
 * on a 24-unit grid with round caps and joins, tinted by the caller.
 * Generated from the design's icon table; circles and rects are paths.
 */
object DGIcons {
    private val paths: Map<String, List<String>> = mapOf(
        "crash" to listOf("M4 15l1.6-4.6A2 2 0 0 1 7.5 9h9a2 2 0 0 1 1.9 1.4L20 15v3a1 1 0 0 1-1 1h-1.5a1 1 0 0 1-1-1v-1h-9v1a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z", "M4 15h16", "M8 5l1.5 2M12 3.5V6M16 5l-1.5 2"),
        "closure" to listOf("M4.5,9h15a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-15a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M7 9l-3 6M12 9l-3 6M17 9l-3 6M21 10.5l-1.5 4.5", "M6 15v5M18 15v5"),
        "hazard" to listOf("M12 3.5l9 16H3z", "M12 10v4.5M12 17.2v.3"),
        "police" to listOf("M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z", "M12 8.5l1.2 2.4 2.6.4-1.9 1.8.5 2.6-2.4-1.3-2.4 1.3.5-2.6-1.9-1.8 2.6-.4z"),
        "traffic" to listOf("M4.5,11h4a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-4a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M15.5,11h4a1.5,1.5 0 0 1 1.5,1.5v3a1.5,1.5 0 0 1 -1.5,1.5h-4a1.5,1.5 0 0 1 -1.5,-1.5v-3a1.5,1.5 0 0 1 1.5,-1.5z", "M5 17v2M8 17v2M16 17v2M19 17v2M10 14h4", "M6.5 7.5h11"),
        "chain" to listOf("M5.5,9h2a3,3 0 0 1 3,3v0a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v0a3,3 0 0 1 3,-3z", "M16.5,9h2a3,3 0 0 1 3,3v0a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v0a3,3 0 0 1 3,-3z", "M8.5 12h7"),
        "fire" to listOf("M12 21c4 0 7-2.7 7-6.6 0-3.4-2.3-5.4-3.6-7.4-.5 1.6-1.4 2.6-2.4 3C13 7 11.5 4.5 9.5 3c.2 3-1.8 4.8-3.2 6.6A7.6 7.6 0 0 0 5 14.4C5 18.3 8 21 12 21z", "M12 21c-1.7 0-3-1.2-3-2.9 0-1.9 1.6-2.7 2.3-4.1.9 1.1 3.7 2.2 3.7 4.1 0 1.7-1.3 2.9-3 2.9z"),
        "ice" to listOf("M12 2.5v19M3.8 7.2l16.4 9.6M3.8 16.8l16.4-9.6", "M9.5 3.8L12 6l2.5-2.2M9.5 20.2L12 18l2.5 2.2"),
        "sign" to listOf("M4,4h16a1.5,1.5 0 0 1 1.5,1.5v8a1.5,1.5 0 0 1 -1.5,1.5h-16a1.5,1.5 0 0 1 -1.5,-1.5v-8a1.5,1.5 0 0 1 1.5,-1.5z", "M6 8h6M6 11h9M12 15v5M8.5 20h7"),
        "camera" to listOf("M5,7h9a2,2 0 0 1 2,2v5a2,2 0 0 1 -2,2h-9a2,2 0 0 1 -2,-2v-5a2,2 0 0 1 2,-2z", "M16 10l5-2.5v8L16 13", "M7.2,11.5a2.3,2.3 0 1,0 4.6,0a2.3,2.3 0 1,0 -4.6,0z"),
        "toll" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M14.6 8.8c-.5-.8-1.5-1.3-2.6-1.3-1.5 0-2.7.8-2.7 2.1 0 2.8 5.6 1.6 5.6 4.5 0 1.3-1.2 2.3-2.9 2.3-1.2 0-2.3-.5-2.8-1.4M12 6v1.5M12 16.5V18"),
        "reroute" to listOf("M6 21V11a4 4 0 0 1 4-4h9", "M15.5 3.5L19 7l-3.5 3.5", "M6 21v-3"),
        "confirm" to listOf("M7 11v9H4.5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z", "M7 11l3.6-7c1.5 0 2.4 1.2 2 2.7L12 10h6a2 2 0 0 1 2 2.3l-1.1 6.3A2 2 0 0 1 16.9 20H7"),
        "speed" to listOf("M4 17a8 8 0 1 1 16 0", "M12 17l4.5-5.5", "M10.7,17a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z"),
        "gps" to listOf("M5.5,12a6.5,6.5 0 1,0 13,0a6.5,6.5 0 1,0 -13,0z", "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M4 4l16 16"),
        "offline" to listOf("M2.5 9a14 14 0 0 1 5-3M21.5 9a14 14 0 0 0-8.3-3.9M5.5 12.5a9.5 9.5 0 0 1 3.4-2.1M18.5 12.5a9.4 9.4 0 0 0-2.3-1.6M9 16a4.5 4.5 0 0 1 4.6-1", "M11.2,19.5a0.8,0.8 0 1,0 1.6,0a0.8,0.8 0 1,0 -1.6,0z", "M3 3l18 18"),
        "watch" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M7.5,12a4.5,4.5 0 1,0 9,0a4.5,4.5 0 1,0 -9,0z", "M11,12a1,1 0 1,0 2,0a1,1 0 1,0 -2,0z"),
        "arrive" to listOf("M5 21V4M5 4h11l-2 4 2 4H5"),
        "home" to listOf("M4 11l8-6.5 8 6.5V20a1 1 0 0 1-1 1h-4.5v-6h-5v6H5a1 1 0 0 1-1-1z"),
        "work" to listOf("M5,7.5h14a2,2 0 0 1 2,2v8a2,2 0 0 1 -2,2h-14a2,2 0 0 1 -2,-2v-8a2,2 0 0 1 2,-2z", "M9 7.5V5.5a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 5.5v2M3 12.5h18"),
        "recent" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M12 7.5V12l3 2"),
        "search" to listOf("M4,10.5a6.5,6.5 0 1,0 13,0a6.5,6.5 0 1,0 -13,0z", "M15.5 15.5L21 21"),
        "layers" to listOf("M12 3l9 5-9 5-9-5z", "M3 13l9 5 9-5"),
        "locate" to listOf("M3 11l18-8-8 18-2-8z"),
        "report" to listOf("M4 20V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H8z", "M12 7.5v4M12 13.6v.2"),
        "close" to listOf("M6 6l12 12M18 6L6 18"),
        "chevron" to listOf("M6 9l6 6 6-6"),
        "up" to listOf("M6 15l6-6 6 6"),
        "right" to listOf("M6 20V12a3 3 0 0 1 3-3h9", "M14 5l4 4-4 4"),
        "straight" to listOf("M12 21V4M7 9l5-5 5 5"),
        "left" to listOf("M18 20V12a3 3 0 0 0-3-3H6", "M10 5L6 9l4 4"),
        "mute" to listOf("M4 9.5h3.5L12 5v14l-4.5-4.5H4z", "M16 9.5c1 .8 1.5 1.6 1.5 2.5s-.5 1.7-1.5 2.5M18.5 7c1.8 1.4 2.7 3.1 2.7 5s-.9 3.6-2.7 5"),
        "share" to listOf("M12 15V3.5M7.5 8L12 3.5 16.5 8", "M5 12v7a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-7"),
        "nav" to listOf("M12 2.5l8.5 18.5-8.5-4.5-8.5 4.5z"),
        "thumb" to listOf("M7 11v9H4.5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1z", "M7 11l3.6-7c1.5 0 2.4 1.2 2 2.7L12 10h6a2 2 0 0 1 2 2.3l-1.1 6.3A2 2 0 0 1 16.9 20H7"),
        "gone" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M8.5 8.5l7 7"),
        "check" to listOf("M5 12.5l4.5 4.5L19 7.5"),
        "plus" to listOf("M12 5v14M5 12h14"),
        "minus" to listOf("M5 12h14"),
        "gear" to listOf("M9,12a3,3 0 1,0 6,0a3,3 0 1,0 -6,0z", "M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"),
    )

    private val cache = HashMap<String, ImageVector>()

    val names: Set<String> get() = paths.keys

    private val pathCache = HashMap<String, List<androidx.compose.ui.graphics.Path>>()

    /** The icon's strokes as paths on the 24-unit grid, for drawing straight onto a canvas. */
    fun strokes(name: String): List<androidx.compose.ui.graphics.Path> = pathCache.getOrPut(name) {
        (paths[name] ?: paths.getValue("hazard")).map { PathParser().parsePathString(it).toPath() }
    }

    /** The icon called [name], or the hazard triangle for one it does not know. */
    fun get(name: String, stroke: Float = 2f): ImageVector = cache.getOrPut("$name/$stroke") {
        val b = ImageVector.Builder(name = "dg.$name", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        for (d in paths[name] ?: paths.getValue("hazard")) {
            b.addPath(
                pathData = PathParser().parsePathString(d).toNodes(),
                stroke = SolidColor(Color.Black), strokeLineWidth = stroke,
                strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round,
            )
        }
        b.build()
    }
}

/** One of [DGIcons], tinted. */
@Composable
fun DGIcon(name: String, tint: Color, size: Dp = 24.dp, modifier: Modifier = Modifier, stroke: Float = 2f, contentDescription: String? = null) {
    Icon(DGIcons.get(name, stroke), contentDescription, modifier.size(size), tint = tint)
}
