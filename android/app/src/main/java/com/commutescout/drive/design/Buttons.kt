package com.commutescout.drive.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Pressed things shrink a little and spring back. */
@Composable
fun Modifier.press(source: MutableInteractionSource): Modifier {
    val down by source.collectIsPressedAsState()
    val s by animateFloatAsState(if (down) .94f else 1f, DG.springy(), label = "press")
    return scale(s)
}

/** The round icon badge: a tone gradient with a white glyph, or a ghost for a spent alert. */
@Composable
fun Disc(icon: String, tone: Tone, size: Dp = DG.disc, ghost: Boolean = false, modifier: Modifier = Modifier) {
    val bg = if (ghost) Brush.linearGradient(listOf(DG.wash, DG.wash))
    else Brush.linearGradient(listOf(tone.color.copy(alpha = .88f).compositeOverWhite(), tone.color))
    Box(modifier.size(size).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
        DGIcon(icon, if (ghost) DG.faint else Color.White, size * .5f, stroke = 2.2f)
    }
}

private fun Color.compositeOverWhite(): Color = Color(1f + (red - 1f) * alpha, 1f + (green - 1f) * alpha, 1f + (blue - 1f) * alpha, 1f)

enum class BtnStyle { PLAIN, PRIMARY, BLUE, DONE, WARN, DANGER, QUIET }

/** The design's 48-tall capsule button. */
@Composable
fun DGButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, style: BtnStyle = BtnStyle.PLAIN, icon: String? = null, enabled: Boolean = true) {
    val src = remember { MutableInteractionSource() }
    val bg by animateColorAsState(when (style) {
        BtnStyle.PRIMARY -> DG.ink
        BtnStyle.BLUE -> DG.low
        BtnStyle.DONE -> DG.good.tint(.14f)
        BtnStyle.PLAIN -> Color.White.copy(alpha = .75f)
    }, label = "btn")
    val fg = when (style) {
        BtnStyle.PRIMARY, BtnStyle.BLUE -> Color.White; BtnStyle.DONE -> DG.goodInk; BtnStyle.PLAIN -> DG.ink
        BtnStyle.WARN, BtnStyle.DANGER -> DG.highInk; BtnStyle.QUIET -> DG.sub
    }.let { if (enabled) it else it.copy(alpha = .45f) }
    val shape = RoundedCornerShape(24.dp)
    Row(
        modifier.press(src).height(DG.btnH).clip(shape).background(bg)
            .then(if (style == BtnStyle.PLAIN || style == BtnStyle.WARN) Modifier.border(0.5.dp, DG.edge, shape) else Modifier)
            .clickable(src, null, enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        if (icon != null) { DGIcon(icon, fg, 19.dp); Spacer(Modifier.width(7.dp)) }
        Text(label, style = DGType.button, color = fg, maxLines = 1)
    }
}

/** A round glass button on the map, an icon in it. */
@Composable
fun GlassRound(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = DG.round, tint: Color = DG.ink, iconSize: Dp = 22.dp) {
    val src = remember { MutableInteractionSource() }
    Box(
        modifier.press(src).size(size).glass(CircleShape, elevation = 12.dp)
            .clickable(src, null, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { DGIcon(icon, tint, iconSize) }
}

/** The small round ghost button inside cards: close, share, show less. */
@Composable
fun GhostRound(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = 36.dp, tint: Color = DG.sub) {
    val src = remember { MutableInteractionSource() }
    Box(
        modifier.press(src).size(size).clip(CircleShape).background(DG.wash)
            .clickable(src, null, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { DGIcon(icon, tint, size * .5f) }
}

/** The blue report button, the one solid thing on the map. */
@Composable
fun ReportButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val src = remember { MutableInteractionSource() }
    Box(
        modifier.press(src).size(DG.report)
            .shadow(16.dp, CircleShape, ambientColor = DG.low, spotColor = DG.low)
            .clip(CircleShape).background(Brush.verticalGradient(listOf(DG.lowTop, DG.low)))
            .clickable(src, null, role = Role.Button, onClick = onClick).semantics { contentDescription = "Report" },
        contentAlignment = Alignment.Center,
    ) { DGIcon("report", Color.White, 26.dp, stroke = 2.2f) }
}

/** 2D and 3D, one glass capsule, the active mode lit. */
@Composable
fun ModeToggle(is3D: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    // One control: a tap anywhere on it switches, as the design's does.
    Column(modifier.width(50.dp).glass(RoundedCornerShape(25.dp), elevation = 12.dp)
        .clickable(role = Role.Switch, onClickLabel = if (is3D) "Show the map in 2D" else "Show the map in 3D", onClick = onToggle)
        .semantics { contentDescription = if (is3D) "3D map, on" else "2D map, on" }
        .padding(4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (three in listOf(false, true)) {
            val on = three == is3D
            val bg by animateColorAsState(if (on) Color.White else Color.Transparent, DG.snap(), label = "mode")
            Box(
                Modifier.size(42.dp, 44.dp).shadow(if (on) 4.dp else 0.dp, RoundedCornerShape(21.dp)).clip(RoundedCornerShape(21.dp)).background(bg),
                contentAlignment = Alignment.Center,
            ) { Text(if (three) "3D" else "2D", style = DGType.label, color = if (on) DG.lowInk else DG.sub) }
        }
    }
}

/** The thin handle at the top of a sheet, or under a tucked alert. */
@Composable
fun Grab(modifier: Modifier = Modifier, width: Dp = 40.dp, color: Color = Color(0x2E0E1726)) {
    Box(modifier.size(width, 5.dp).clip(CircleShape).background(color))
}

/** A testable click target wrapper: keeps the app's test tags on the new controls. */
fun Modifier.tag(t: String): Modifier = testTag(t)
