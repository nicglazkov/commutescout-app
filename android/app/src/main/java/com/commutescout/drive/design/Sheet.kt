package com.commutescout.drive.design

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * A bottom sheet that stops at [snaps] (heights from the bottom, low to
 * high). It follows the finger while dragged, then springs to the snap
 * the fling points at. A drag below the lowest snap by more than a
 * third of it calls onDismiss.
 */
@Stable
class SheetState(val snapsPx: List<Float>, start: Int, private val scope: CoroutineScope, private val onSnap: (Int) -> Unit, private val onDismiss: (() -> Unit)?) {
    val height = Animatable(snapsPx[start])
    var index by mutableIntStateOf(start)
        private set

    /** 0 at the lowest snap, 1 at the highest: what the sheet's pulled-up parts fade with. */
    val pulled: Float get() {
        val lo = snapsPx.first(); val hi = snapsPx.last()
        return if (hi <= lo) 0f else ((height.value - lo) / (hi - lo)).coerceIn(0f, 1f)
    }

    fun dragBy(dy: Float) { scope.launch { height.snapTo((height.value - dy).coerceIn(snapsPx.first() * .4f, snapsPx.last() * 1.04f)) } }

    fun settle(velocityY: Float) {
        val h = height.value
        if (onDismiss != null && h < snapsPx.first() * .72f) { onDismiss.invoke(); return }
        // A fling picks the next snap its way; a slow release, the nearest.
        val target = when {
            velocityY < -900f -> snapsPx.indexOfFirst { it > h + 1 }.takeIf { it >= 0 } ?: snapsPx.lastIndex
            velocityY > 900f -> snapsPx.indexOfLast { it < h - 1 }.takeIf { it >= 0 } ?: 0
            else -> snapsPx.indices.minBy { abs(snapsPx[it] - h) }
        }
        snapTo(target, velocityY)
    }

    fun snapTo(i: Int, velocityY: Float = 0f) {
        index = i.coerceIn(0, snapsPx.lastIndex)
        onSnap(index)
        scope.launch { height.animateTo(snapsPx[index], DG.snap(), initialVelocity = -velocityY) }
    }
}

@Composable
fun rememberSheetState(snaps: List<Dp>, start: Int = 0, onSnap: (Int) -> Unit = {}, onDismiss: (() -> Unit)? = null): SheetState {
    val d = LocalDensity.current
    val scope = rememberCoroutineScope()
    return remember(snaps) { SheetState(snaps.map { with(d) { it.toPx() } }, start, scope, onSnap, onDismiss) }
}

/**
 * The sheet itself, glass with a 30 dp top radius and a grab handle.
 * Content that scrolls hands the drag to the sheet at its top, so one
 * pull moves the sheet and then the page, as on iOS.
 */
@Composable
fun DGSheet(state: SheetState, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val d = LocalDensity.current
    val nested = remember(state) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Pulling up grows the sheet before the page scrolls.
                if (available.y < 0 && state.height.value < state.snapsPx.last() - 0.5f) { state.dragBy(available.y); return Offset(0f, available.y) }
                return Offset.Zero
            }
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                // At the top of the page, pulling down shrinks the sheet.
                if (available.y > 0 && source == NestedScrollSource.UserInput) { state.dragBy(available.y); return Offset(0f, available.y) }
                return Offset.Zero
            }
            override suspend fun onPreFling(available: Velocity): Velocity {
                val h = state.height.value
                if (state.snapsPx.none { abs(it - h) < 1f }) { state.settle(available.y); return available }
                return Velocity.Zero
            }
        }
    }
    val tracker = remember { VelocityTracker() }
    // The sheet moves under the finger, so the finger's own position is
    // not a steady frame: track the drag's running total instead.
    val acc = remember { floatArrayOf(0f) }
    Column(
        modifier.fillMaxWidth().height(with(d) { state.height.value.toDp() })
            .glass(RoundedCornerShape(topStart = DG.rSheet, topEnd = DG.rSheet), elevation = 24.dp, strong = true)
            .nestedScroll(nested)
            .pointerInput(state) {
                detectVerticalDragGestures(
                    onDragStart = { tracker.resetTracking(); acc[0] = 0f },
                    onDragEnd = { state.settle(tracker.calculateVelocity().y) },
                    onDragCancel = { state.settle(0f) },
                ) { change, dy -> acc[0] += dy; tracker.addPosition(change.uptimeMillis, Offset(0f, acc[0])); state.dragBy(dy) }
            },
    ) {
        Box(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 6.dp), contentAlignment = Alignment.Center) { Grab() }
        content()
    }
}
