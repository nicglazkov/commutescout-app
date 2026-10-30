package com.commutescout.drive.design

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Day Glass+ tokens, taken from the design's CSS. Every screen draws
 * with these, so a color or a radius changes in one place.
 */
object DG {
    // Ink and surfaces.
    val ink = Color(0xFF0E1726)
    val sub = Color(0xFF586377)
    val faint = Color(0xFF8A94A6)
    val hair = Color(0x140E1726)          // rgba(14,23,38,.08)
    val edge = Color(0x1A0E1726)          // the glass hairline, .10
    val bg = Color(0xFFF4F6F9)
    val wash = Color(0x0D0E1726)          // ghost buttons, .05

    // Tones: the dot color, and the darker ink for words on a tint.
    val high = Color(0xFFE5484D)
    val mid = Color(0xFFEE8B0C)
    val low = Color(0xFF2F7CF6)
    val clear = Color(0xFF8A94A6)
    val good = Color(0xFF14A35A)
    val highInk = Color(0xFFB4232B)
    val midInk = Color(0xFFA05A00)
    val lowInk = Color(0xFF1F5FCF)
    val goodInk = Color(0xFF0D7A42)
    val clearInk = Color(0xFF586377)
    val lowTop = Color(0xFF4A8FF8)        // the blue gradient's light end

    // Lanes.
    val laneOff = Color(0xFFB3BCCB)
    val laneFill = Color(0xFFDFE5EC)

    // Sizes.
    val gutter = 14.dp
    val manH = 158.dp
    val tuck = 26.dp
    val rCard = 28.dp
    val rSheet = 30.dp
    val rThumb = 16.dp
    val disc = 44.dp
    val discSm = 36.dp
    val btnH = 48.dp
    val round = 50.dp
    val report = 56.dp

    // Motion: the design's springs (stiffness, damping) as Compose specs.
    // dampingRatio = damping / (2 * sqrt(stiffness)).
    fun <T> springy() = spring<T>(dampingRatio = 0.66f, stiffness = 230f)
    fun <T> soft() = spring<T>(dampingRatio = 0.86f, stiffness = 210f)
    fun <T> snap() = spring<T>(dampingRatio = 0.81f, stiffness = 220f)
    fun <T> slide() = spring<T>(dampingRatio = 0.84f, stiffness = 170f)
    fun <T> settle() = spring<T>(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow)

    val easeOut = CubicBezierEasing(.16f, 1f, .3f, 1f)
    val easeInOut = CubicBezierEasing(.65f, 0f, .35f, 1f)
    val hideEase = CubicBezierEasing(.55f, 0f, .25f, 1f)
    /** The map camera making room, and giving it back. */
    fun <T> camera() = tween<T>(900, easing = easeOut)
    fun <T> tilt() = tween<T>(1100, easing = easeInOut)
}

/** How loud an alert is, which picks its tint. */
enum class Tone(val color: Color, val ink: Color) {
    HIGH(DG.high, DG.highInk),
    MID(DG.mid, DG.midInk),
    LOW(DG.low, DG.lowInk),
    CLEAR(DG.clear, DG.clearInk),
    GOOD(DG.good, DG.goodInk),
}

/** Mixes [this] over white by [amount]: the CSS color-mix the design uses. */
fun Color.tint(amount: Float): Color = Color(
    red = 1f + (red - 1f) * amount, green = 1f + (green - 1f) * amount, blue = 1f + (blue - 1f) * amount, alpha = 1f,
)
