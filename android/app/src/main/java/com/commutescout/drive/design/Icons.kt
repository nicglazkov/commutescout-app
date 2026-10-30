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
        "plane" to listOf("M10.5 3.8a1.5 1.5 0 0 1 3 0V9l7.5 4.6V16l-7.5-2.4v4.6l2.2 1.6V21L12 20l-3.7 1v-1.2l2.2-1.6v-4.6L3 16v-2.4L10.5 9z"),
        "pin" to listOf("M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z", "M9.6,10a2.4,2.4 0 1,0 4.8,0a2.4,2.4 0 1,0 -4.8,0z"),
        "train" to listOf("M8.5,3h7a3,3 0 0 1 3,3v7.5a3,3 0 0 1 -3,3h-7a3,3 0 0 1 -3,-3v-7.5a3,3 0 0 1 3,-3z", "M5.5 10.5h13M9 21l1.4-4.5M15 21l-1.4-4.5", "M9 13.5h.01M15 13.5h.01"),
        "school" to listOf("M2.5 9.5L12 5l9.5 4.5L12 14z", "M6.5 11.5v4.8c1.6 1.4 3.5 2.1 5.5 2.1s3.9-.7 5.5-2.1v-4.8M21.5 9.5v4.5"),
        "star" to listOf("M12 3.4l2.65 5.4 5.95.86-4.3 4.2 1 5.94L12 17l-5.3 2.8 1-5.94-4.3-4.2 5.95-.86z"),
        "back" to listOf("M15 5l-7 7 7 7"),
        "download" to listOf("M12 4v10.5M7.5 10L12 14.5 16.5 10", "M5 19.5h14"),
        "fog" to listOf("M5 8h10M3.5 12h15M6 16h13M9 20h7"),
        "flood" to listOf("M6 11V7.8L12 3.5l6 4.3V11", "M3 15c1.5 0 1.5-1.2 3-1.2s1.5 1.2 3 1.2 1.5-1.2 3-1.2 1.5 1.2 3 1.2 1.5-1.2 3-1.2 1.5 1.2 3 1.2M3 19.5c1.5 0 1.5-1.2 3-1.2s1.5 1.2 3 1.2 1.5-1.2 3-1.2 1.5 1.2 3 1.2 1.5-1.2 3-1.2 1.5 1.2 3 1.2"),
        "carside" to listOf("M3 15.5V13l2.2-4H14l4 4h2a1 1 0 0 1 1 1v1.5", "M5,16a2,2 0 1,0 4,0a2,2 0 1,0 -4,0z", "M15,16a2,2 0 1,0 4,0a2,2 0 1,0 -4,0z", "M9 16h6"),
        "lane" to listOf("M6.5 21L9.5 3M17.5 21L14.5 3M12 4v3M12 10.5v3M12 17v3"),
        "mapi" to listOf("M3 6.5l6-2.5 6 2.5 6-2.5v13.5l-6 2.5-6-2.5-6 2.5z", "M9 4v13.5M15 6.5V20"),
        "del" to listOf("M8.5 5.5H20a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H8.5L3 12z", "M11.5 9.5l5 5M16.5 9.5l-5 5"),
        "shift" to listOf("M12 4.5l7.5 7.5h-4v7h-7v-7h-4z"),
        "globe" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M3.5 12h17M12 3.5c2.4 2.5 3.4 5.4 3.4 8.5s-1 6-3.4 8.5c-2.4-2.5-3.4-5.4-3.4-8.5s1-6 3.4-8.5z"),
        "mic" to listOf("M12,3h0a3,3 0 0 1 3,3v5a3,3 0 0 1 -3,3h-0a3,3 0 0 1 -3,-3v-5a3,3 0 0 1 3,-3z", "M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"),
        "pencil" to listOf("M4 20l1-4L16 5l3 3L8 19z"),
        "bell" to listOf("M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z", "M10 20.5a2 2 0 0 0 4 0"),
        "backA" to listOf("M20 12H5M11 5l-7 7 7 7"),
        "chevR" to listOf("M9.5 5.5l6.5 6.5-6.5 6.5"),
        "map" to listOf("M9 4.5L3.5 6.8v13l5.5-2.3 6 2.3 5.5-2.3v-13L15 6.8z", "M9 4.5v13M15 6.8v13"),
        "ruler" to listOf("M4.3,8h15.4a1.8,1.8 0 0 1 1.8,1.8v4.9a1.8,1.8 0 0 1 -1.8,1.8h-15.4a1.8,1.8 0 0 1 -1.8,-1.8v-4.9a1.8,1.8 0 0 1 1.8,-1.8z", "M6.5 8v3M10.5 8v4.5M14.5 8v3M18.5 8v4.5"),
        "speaker" to listOf("M4 9.5h3.5L12 5v14l-4.5-4.5H4z", "M16 9.5c1 .8 1.5 1.6 1.5 2.5s-.5 1.7-1.5 2.5M18.5 7c1.8 1.4 2.7 3.1 2.7 5s-.9 3.6-2.7 5"),
        "puzzle" to listOf("M10 4a2 2 0 0 1 4 0v1.5h3.5a1 1 0 0 1 1 1V10H17a2 2 0 0 0 0 4h1.5v3.5a1 1 0 0 1-1 1H14V17a2 2 0 0 0-4 0v1.5H6.5a1 1 0 0 1-1-1V14H7a2 2 0 0 0 0-4H5.5V6.5a1 1 0 0 1 1-1H10z"),
        "antenna" to listOf("M10,10a2,2 0 1,0 4,0a2,2 0 1,0 -4,0z", "M12 12v8.5M8.3 6.3a5.3 5.3 0 0 0 0 7.4M15.7 6.3a5.3 5.3 0 0 1 0 7.4M5.6 3.7a9 9 0 0 0 0 12.6M18.4 3.7a9 9 0 0 1 0 12.6"),
        "help" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M9.6 9.5a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.1-2.4 3.6M12 16.8v.2"),
        "play" to listOf("M8.5 5.8v12.4a.8.8 0 0 0 1.2.7l9.6-6.2a.8.8 0 0 0 0-1.4L9.7 5.1a.8.8 0 0 0-1.2.7z"),
        "stop" to listOf("M9,7h6a2,2 0 0 1 2,2v6a2,2 0 0 1 -2,2h-6a2,2 0 0 1 -2,-2v-6a2,2 0 0 1 2,-2z"),
        "key" to listOf("M4,15a4,4 0 1,0 8,0a4,4 0 1,0 -8,0z", "M11 12l8.5-8.5M16.5 6.5L19 9M14 9.5l2 2"),
        "logout" to listOf("M14 4h4a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-4", "M10 8l-4 4 4 4M6 12h9"),
        "thermo" to listOf("M10 14.5V5a2 2 0 0 1 4 0v9.5a4 4 0 1 1-4 0z", "M12 9v8"),
        "refresh" to listOf("M19.5 12a7.5 7.5 0 1 1-2.2-5.3", "M19.5 4.5v4h-4"),
        "devices" to listOf("M4.5,5h10a1.5,1.5 0 0 1 1.5,1.5v7a1.5,1.5 0 0 1 -1.5,1.5h-10a1.5,1.5 0 0 1 -1.5,-1.5v-7a1.5,1.5 0 0 1 1.5,-1.5z", "M7 19h5", "M16.8,9h2.9a1.3,1.3 0 0 1 1.3,1.3v7.9a1.3,1.3 0 0 1 -1.3,1.3h-2.9a1.3,1.3 0 0 1 -1.3,-1.3v-7.9a1.3,1.3 0 0 1 1.3,-1.3z"),
        "route" to listOf("M3.8,18a2.2,2.2 0 1,0 4.4,0a2.2,2.2 0 1,0 -4.4,0z", "M15.8,6a2.2,2.2 0 1,0 4.4,0a2.2,2.2 0 1,0 -4.4,0z", "M8 18h7.5a3 3 0 0 0 0-6h-7a3 3 0 0 1 0-6H16"),
        "shield" to listOf("M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z", "M9 12l2.2 2.2L15.5 10"),
        "leaf" to listOf("M5 19c0-8 5-13 14-14 0 9-5 14-13 14z", "M5 19l7-7"),
        "next" to listOf("M9 5l7 7-7 7"),
        "bolt" to listOf("M13.5 2.5L5.5 13.5h6l-1 8 8-11h-6z"),
        "fuel" to listOf("M4.5 21V5a2 2 0 0 1 2-2h5.5a2 2 0 0 1 2 2v16M3 21h12.5", "M7 7.5h4.5", "M14 10h1.8a2 2 0 0 1 2 2v4.3a1.5 1.5 0 0 0 3 0V8.2L18 5.5"),
        "air" to listOf("M3 8.5h10a3 3 0 1 0-3-3", "M3 12.5h14.5a3 3 0 1 1-3 3", "M3 16.5h6"),
        "radar" to listOf("M10.3,13.5a1.7,1.7 0 1,0 3.4,0a1.7,1.7 0 1,0 -3.4,0z", "M8.3 9.8a5.2 5.2 0 0 1 7.4 0M5.4 6.9a9.3 9.3 0 0 1 13.2 0", "M12 15.2V21M8.5 21h7"),
        "people" to listOf("M5.8,8a3.2,3.2 0 1,0 6.4,0a3.2,3.2 0 1,0 -6.4,0z", "M3 20a6 6 0 0 1 12 0", "M14.5,9a2.5,2.5 0 1,0 5,0a2.5,2.5 0 1,0 -5,0z", "M16.2 14.2a5 5 0 0 1 5.3 5"),
        "light" to listOf("M11,2.5h2a3,3 0 0 1 3,3v10a3,3 0 0 1 -3,3h-2a3,3 0 0 1 -3,-3v-10a3,3 0 0 1 3,-3z", "M10.7,6.6a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M10.7,10.5a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M10.7,14.4a1.3,1.3 0 1,0 2.6,0a1.3,1.3 0 1,0 -2.6,0z", "M12 18.5V22"),
        "lock" to listOf("M7.5,10.5h9a2.5,2.5 0 0 1 2.5,2.5v5a2.5,2.5 0 0 1 -2.5,2.5h-9a2.5,2.5 0 0 1 -2.5,-2.5v-5a2.5,2.5 0 0 1 2.5,-2.5z", "M8 10.5V8a4 4 0 0 1 8 0v2.5"),
        "pinl" to listOf("M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z", "M9.6,10a2.4,2.4 0 1,0 4.8,0a2.4,2.4 0 1,0 -4.8,0z"),
        "moon" to listOf("M19.5 14.6A7.8 7.8 0 0 1 9.4 4.5a7.8 7.8 0 1 0 10.1 10.1z"),
        "mail" to listOf("M5.5,5.5h13a2.5,2.5 0 0 1 2.5,2.5v8a2.5,2.5 0 0 1 -2.5,2.5h-13a2.5,2.5 0 0 1 -2.5,-2.5v-8a2.5,2.5 0 0 1 2.5,-2.5z", "M3.8 7.2l8.2 5.8 8.2-5.8"),
        "wifi" to listOf("M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M9 16a4.5 4.5 0 0 1 6 0", "M11.1,19.5a0.9,0.9 0 1,0 1.8,0a0.9,0.9 0 1,0 -1.8,0z"),
        "trash" to listOf("M4.5 6.5h15M9.5 6.5v-2h5v2M6.5 6.5l1 13a1.5 1.5 0 0 0 1.5 1.4h6a1.5 1.5 0 0 0 1.5-1.4l1-13", "M10 10.5v6.5M14 10.5v6.5"),
        "store" to listOf("M4 9.5L5.5 4h13L20 9.5", "M4 9.5a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0", "M5.5 12.5V20h13v-7.5"),
        "ring" to listOf("M4,12a8,8 0 1,0 16,0a8,8 0 1,0 -16,0z", "M10.4,12a1.6,1.6 0 1,0 3.2,0a1.6,1.6 0 1,0 -3.2,0z"),
        "shape" to listOf("M5 8.5l6.5-5 8 4.5-2.2 11L6.5 20z"),
        "piece" to listOf("M10 4.5a2 2 0 0 1 4 0V6h3.5a1 1 0 0 1 1 1v3.5H17a2 2 0 0 0 0 4h1.5V18a1 1 0 0 1-1 1H14v-1.5a2 2 0 0 0-4 0V19H6.5a1 1 0 0 1-1-1v-3.5H7a2 2 0 0 0 0-4H5.5V7a1 1 0 0 1 1-1H10z"),
        "eye" to listOf("M2.5 12s3.5-6.5 9.5-6.5 9.5 6.5 9.5 6.5-3.5 6.5-9.5 6.5S2.5 12 2.5 12z", "M9.2,12a2.8,2.8 0 1,0 5.6,0a2.8,2.8 0 1,0 -5.6,0z"),
        "nope" to listOf("M3.5,12a8.5,8.5 0 1,0 17,0a8.5,8.5 0 1,0 -17,0z", "M6 6l12 12"),
        "phone" to listOf("M9,2.5h6a2.5,2.5 0 0 1 2.5,2.5v14a2.5,2.5 0 0 1 -2.5,2.5h-6a2.5,2.5 0 0 1 -2.5,-2.5v-14a2.5,2.5 0 0 1 2.5,-2.5z", "M10.5 18.5h3"),
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
