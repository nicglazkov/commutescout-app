package com.commutescout.drive.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.commutescout.drive.R

/**
 * Onest, bundled (SIL Open Font License, assets/fonts/Onest-OFL.txt).
 * One variable file serves every weight the design uses.
 */
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
val Onest: FontFamily = FontFamily(
    listOf(400, 500, 600, 700, 800).map { w ->
        Font(R.font.onest, FontWeight(w), variationSettings = FontVariation.Settings(FontVariation.weight(w)))
    },
)

/** The design's type scale, by job. Sizes are the mockup's px as sp. */
object DGType {
    private fun s(size: Float, weight: Int, tracking: Float = 0f, line: Float = 1.25f) = TextStyle(
        fontFamily = Onest, fontSize = size.sp, fontWeight = FontWeight(weight),
        letterSpacing = if (tracking == 0f) TextUnit.Unspecified else tracking.em, lineHeight = (size * line).sp,
    )

    val maneuverDist = s(34f, 700, -0.02f, 1.0f)
    val maneuverUnit = s(18f, 600)
    val maneuverRoad = s(18f, 600, -0.01f)
    val maneuverThen = s(14f, 500)
    val sheetTitle = s(24f, 700, -0.02f, 1.15f)
    val cardTitle = s(22f, 700, -0.02f, 1.15f)
    val alertTitle = s(19f, 700, -0.015f, 1.15f)
    val alertBody = s(14.5f, 500)
    val alertDist = s(25f, 700, -0.02f, 1.0f)
    val bigDist = s(28f, 700, -0.02f, 1.0f)
    val eta = s(26f, 700, -0.02f, 1.0f)
    val speed = s(30f, 700, -0.03f, 1.0f)
    val title = s(17f, 700, -0.01f)
    val row = s(16f, 600, -0.01f)
    val body = s(15f, 500, 0f, 1.4f)
    val lede = s(16.5f, 500, 0f, 1.45f)
    val small = s(13.5f, 500)
    val meta = s(14f, 500)
    val label = s(13f, 700)
    val tiny = s(11.5f, 600)
    val button = s(16f, 600)
    val search = s(17f, 500)
    val mono = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.Medium)
}

/** Material's slots in Onest, so every screen not yet restyled still reads in the new face. */
fun onestTypography(): Typography {
    val base = Typography()
    fun TextStyle.o() = copy(fontFamily = Onest)
    return Typography(
        displayLarge = base.displayLarge.o(), displayMedium = base.displayMedium.o(), displaySmall = base.displaySmall.o(),
        headlineLarge = base.headlineLarge.o(), headlineMedium = base.headlineMedium.o(), headlineSmall = base.headlineSmall.o(),
        titleLarge = base.titleLarge.o(), titleMedium = base.titleMedium.o(), titleSmall = base.titleSmall.o(),
        bodyLarge = base.bodyLarge.o(), bodyMedium = base.bodyMedium.o(), bodySmall = base.bodySmall.o(),
        labelLarge = base.labelLarge.o(), labelMedium = base.labelMedium.o(), labelSmall = base.labelSmall.o(),
    )
}

/** The app theme with Onest throughout; colors stay as the caller sets them. */
@Composable
fun DayGlassTheme(colorScheme: androidx.compose.material3.ColorScheme, content: @Composable () -> Unit) {
    // Light mode maps Material roles onto the Day Glass+ tokens, so the
    // sheets and cards not yet drawn with the design's own parts still
    // read as one app. Dark mode keeps the scheme it is given.
    val scheme = if (colorScheme.background.luminance() > 0.5f) colorScheme.copy(
        primary = DG.low, onPrimary = Color.White, surface = Color(0xFFFBFCFE), onSurface = DG.ink,
        surfaceVariant = Color(0xFFEEF1F6), onSurfaceVariant = DG.sub, outline = DG.edge, outlineVariant = DG.hair,
        background = DG.bg, onBackground = DG.ink, surfaceContainerLow = Color(0xFFF7F8FB), surfaceContainer = Color(0xFFF4F6F9),
        surfaceContainerHigh = Color(0xFFF1F3F7), error = DG.high,
    ) else colorScheme
    MaterialTheme(colorScheme = scheme, typography = onestTypography(), content = content)
}
