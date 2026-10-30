package com.commutescout.drive.design

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/**
 * A sheet as tall as what it holds, for the trip pages (place, routes,
 * report, arrive). It rises on a spring when it first shows, follows the
 * finger when dragged, and settles back, or leaves when pulled down past
 * a third of its height. A change in what it holds springs its height.
 * [scrim] catches taps above it (they close it), for sheets that sit
 * over the map rather than beside it.
 */
@Composable
fun FitSheet(
    modifier: Modifier = Modifier,
    onDismiss: (() -> Unit)? = null,
    scrim: Boolean = false,
    rise: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val scope = rememberCoroutineScope()
    val enter = remember { Animatable(if (rise) 1f else 0f) }
    val drag = remember { Animatable(0f) }
    val height = remember { floatArrayOf(1f) }
    LaunchedEffect(Unit) { if (rise) enter.animateTo(0f, DG.snap()) }
    fun leave() {
        val done = onDismiss ?: return
        scope.launch { drag.animateTo(height[0], tween(260, easing = DG.hideEase)); done() }
    }
    if (onDismiss != null) BackHandler { leave() }
    val tracker = remember { VelocityTracker() }
    val acc = remember { floatArrayOf(0f) }
    val sheet = @Composable { m: Modifier ->
        Column(
            m.fillMaxWidth()
                .onSizeChanged { height[0] = it.height.toFloat().coerceAtLeast(1f) }
                .graphicsLayer { translationY = enter.value * size.height + drag.value }
                .glass(RoundedCornerShape(topStart = DG.rSheet, topEnd = DG.rSheet), elevation = 24.dp, strong = true)
                // Taps on the sheet's background never fall through to the map.
                .clickable(remember { MutableInteractionSource() }, null) {}
                .pointerInput(onDismiss) {
                    detectVerticalDragGestures(
                        onDragStart = { tracker.resetTracking(); acc[0] = 0f },
                        onDragEnd = {
                            val v = tracker.calculateVelocity().y
                            if (onDismiss != null && (drag.value > height[0] / 3 || v > 1400f)) leave()
                            else scope.launch { drag.animateTo(0f, DG.snap(), initialVelocity = v) }
                        },
                        onDragCancel = { scope.launch { drag.animateTo(0f, DG.snap()) } },
                    ) { change, dy ->
                        acc[0] += dy
                        tracker.addPosition(change.uptimeMillis, Offset(0f, acc[0]))
                        // Down follows the finger; up gives a little and stops.
                        val next = drag.value + if (drag.value + dy < 0) dy * .25f else dy
                        scope.launch { drag.snapTo(next.coerceAtLeast(-28f)) }
                    }
                }
                .animateContentSize(DG.snap()),
        ) {
            Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 6.dp), contentAlignment = Alignment.Center) { Grab(color = Color(0x290E1726)) }
            content()
        }
    }
    if (scrim) Box(modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) { leave() })
        sheet(Modifier.align(Alignment.BottomCenter))
    } else sheet(modifier)
}

/** The bar of main buttons at a sheet's foot: a hairline over it and room for the system bar. */
@Composable
fun SheetActions(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Column(modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(DG.hair))
        Row(
            Modifier.fillMaxWidth().background(Color.White.copy(alpha = .6f)).navigationBarsPadding()
                .padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, content = content,
        )
    }
}

/** A sheet's head: an optional disc, the title, a line under it and an optional close button. */
@Composable
fun SheetHead(
    title: String, sub: String?, modifier: Modifier = Modifier,
    lead: (@Composable () -> Unit)? = null, onClose: (() -> Unit)? = null, closeModifier: Modifier = Modifier,
) {
    Row(modifier.fillMaxWidth().padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        if (lead != null) { lead(); Spacer(Modifier.width(14.dp)) }
        Column(Modifier.weight(1f)) {
            Text(title, style = DGType.sheetTitle, color = DG.ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, Modifier.padding(top = 3.dp), style = DGType.alertBody, color = DG.sub, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (onClose != null) Box(Modifier.align(Alignment.Top).padding(start = 8.dp)) {
            GhostRound("close", "Close", onClose, closeModifier, size = 36.dp)
        }
    }
}

/** The small grey heading over a part of a sheet, with an optional colored dot. */
@Composable
fun SheetLabel(text: String, modifier: Modifier = Modifier, dot: Color? = null) {
    Row(modifier.padding(start = 22.dp, end = 22.dp, top = 18.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (dot != null) { Box(Modifier.width(8.dp).height(8.dp).background(dot, RoundedCornerShape(4.dp))); Spacer(Modifier.width(8.dp)) }
        Text(text, style = PageType.groupHead, color = DG.sub)
    }
}
