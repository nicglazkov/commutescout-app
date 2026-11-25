package com.commutescout.drive.design

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Day Glass+ tokens, taken from the design's CSS. Every screen draws
 * with these, so a color or a radius changes in one place.
 */
object DG {
    /**
     * Whether the app is drawing dark. The root sets it from the theme
     * setting; it is snapshot state, so everything that reads a color
     * below redraws when it flips.
     */
    var dark by mutableStateOf(false)

    private fun pick(light: Long, night: Long) = Color(if (dark) night else light)

    // Ink and surfaces.
    val ink get() = pick(0xFF0E1726, 0xFFF1F4F9)
    val sub get() = pick(0xFF586377, 0xFFA9B4C6)
    val faint get() = pick(0xFF8A94A6, 0xFF7C8799)
    val hair get() = pick(0x140E1726, 0x1FFFFFFF)          // rgba(14,23,38,.08)
    val edge get() = pick(0x1A0E1726, 0x29FFFFFF)          // the glass hairline, .10
    val bg get() = pick(0xFFF4F6F9, 0xFF0B1320)
    val wash get() = pick(0x0D0E1726, 0x14FFFFFF)          // ghost buttons, .05
    /** A solid card or sheet: white by day. */
    val surface get() = pick(0xFFFFFFFF, 0xFF18212F)
    /** A full-screen page behind cards. */
    val page get() = pick(0xFFECF1F6, 0xFF0D1522)
    /** The page color where a header fades over the list. */
    val pageTop get() = pick(0xFFF0F4F8, 0xFF101A28)
    /** A sheet's own gradient, top and bottom. */
    val sheetTop get() = pick(0xFFF8FAFC, 0xFF18212F)
    val sheetBottom get() = pick(0xFFF3F6FA, 0xFF141C29)
    /** A switch's track when off. */
    val track get() = pick(0xFFE6EAF0, 0xFF2A3546)
    /** Words on a pale blue note. */
    val noteInk get() = pick(0xFF23406F, 0xFFC3D6F7)
    /** A chip lifted off its track: the picked segment. */
    val raised get() = pick(0xFFFFFFFF, 0xFF34425A)
    /** A solid dark button or tile that carries white words. */
    val solid get() = pick(0xFF0E1726, 0xFF2D3A50)
    /** The dim behind a dialog. */
    val scrim get() = pick(0x290E1726, 0x8C000000)
    /** A drop shadow at [alpha]; black at night, where an ink shadow would glow. */
    fun shadow(alpha: Float): Color = if (dark) Color.Black.copy(alpha = (alpha * 2f).coerceAtMost(.7f)) else Color(0xFF0E1726).copy(alpha = alpha)
    /** The shadow under glass. */
    val shade get() = pick(0x4D0E1726, 0x99000000)
    /** The lit rim along the top of glass. */
    val rim get() = pick(0xD9FFFFFF, 0x1AFFFFFF)
    /** A translucent card: white at [alpha] by day, a raised navy at night. */
    fun glass(alpha: Float): Color = if (dark) Color(0xFF1E2838).copy(alpha = alpha) else Color.White.copy(alpha = alpha)

    // Tones: the dot color, and the ink for words on a tint (darker by
    // day, lighter at night).
    val high = Color(0xFFE5484D)
    val mid = Color(0xFFEE8B0C)
    val low = Color(0xFF2F7CF6)
    val clear = Color(0xFF8A94A6)
    val good = Color(0xFF14A35A)
    val highInk get() = pick(0xFFB4232B, 0xFFFF9396)
    val midInk get() = pick(0xFFA05A00, 0xFFFFB85C)
    val lowInk get() = pick(0xFF1F5FCF, 0xFF8AB4F8)
    val goodInk get() = pick(0xFF0D7A42, 0xFF5FD597)
    val clearInk get() = pick(0xFF586377, 0xFFA9B4C6)
    val lowTop = Color(0xFF4A8FF8)        // the blue gradient's light end
    val plug = Color(0xFF7C5CF0)          // plugin data, always purple
    val plugInk get() = pick(0xFF5A3CC8, 0xFFB7A4FF)
    val chev get() = pick(0xFFB3BCCB, 0xFF566175)          // row chevrons

    // Lanes.
    val laneOff get() = pick(0xFFB3BCCB, 0xFF566175)
    val laneFill get() = pick(0xFFDFE5EC, 0xFF2A3546)
    /** Lane lines and the road's edge on a lane drawing. */
    val laneLine get() = pick(0xFFFFFFFF, 0xFF5B677A)

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
enum class Tone(val color: Color) {
    HIGH(DG.high), MID(DG.mid), LOW(DG.low), CLEAR(DG.clear), GOOD(DG.good);

    /** The ink for words on this tone's tint. */
    val ink: Color get() = when (this) {
        HIGH -> DG.highInk; MID -> DG.midInk; LOW -> DG.lowInk; CLEAR -> DG.clearInk; GOOD -> DG.goodInk
    }
}

/**
 * Mixes [this] over the card color by [amount]: the CSS color-mix the
 * design uses over white. At night the card is dark, and the mix runs a
 * little stronger so a tint still reads.
 */
fun Color.tint(amount: Float): Color {
    val base = DG.surface
    val a = if (DG.dark) (amount * 1.7f).coerceAtMost(1f) else amount
    return Color(
        red = base.red + (red - base.red) * a, green = base.green + (green - base.green) * a,
        blue = base.blue + (blue - base.blue) * a, alpha = 1f,
    )
}
