package com.commutescout.drive.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/*
 * Frosted glass. The map under the chrome is a SurfaceView, which a
 * Compose blur cannot see through, so the frost is emulated: a bright
 * translucent wash, a hairline edge, a lit top rim and a long soft
 * shadow. Over the light map styles it reads as the design's glass.
 */

/**
 * The glass look on any shape. [tone] tints it for an alert (13% at the
 * top falling to 4%, the edge and the shadow in the tone too).
 */
fun Modifier.glass(shape: Shape, tone: Tone? = null, elevation: Dp = 18.dp, strong: Boolean = false): Modifier {
    val tint = tone?.color
    val top = if (tint != null) tint.tint(.13f).copy(alpha = .93f) else Color.White.copy(alpha = if (strong) .95f else .90f)
    val bottom = if (tint != null) tint.tint(.04f).copy(alpha = .88f) else Color.White.copy(alpha = if (strong) .90f else .82f)
    val edge = tint?.copy(alpha = .26f) ?: DG.edge
    val shade = tint?.copy(alpha = .45f) ?: Color(0xFF0E1726).copy(alpha = .30f)
    return this
        .shadow(elevation, shape, clip = false, ambientColor = shade, spotColor = shade)
        .clip(shape)
        .background(Brush.verticalGradient(listOf(top, bottom)))
        .drawWithContent {
            drawContent()
            // The lit rim along the top edge.
            drawLine(Color.White.copy(alpha = .85f), Offset(size.height * .3f, .75f), Offset(size.width - size.height * .3f, .75f), 1.5f)
        }
        .border(0.5.dp, edge, shape)
}

/** A box in glass. */
@Composable
fun Glass(shape: Shape, modifier: Modifier = Modifier, tone: Tone? = null, elevation: Dp = 18.dp, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.glass(shape, tone, elevation), content = content)
}

/** The see-more veil over the map: a light frost that keeps the road readable. */
fun Modifier.veil(soft: Boolean = false): Modifier = background(Color(0xFFECF1F6).copy(alpha = if (soft) .22f else .38f))
