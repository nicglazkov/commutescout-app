package com.commutescout.drive.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import kotlinx.coroutines.launch

/**
 * A full-screen layer over everything, map included: a window of its
 * own, so a page or sheet opened from inside another sheet still covers
 * the whole screen. No dim and no window animation: what it holds moves
 * itself. Back calls [onBack].
 */
@Composable
fun DGLayer(onBack: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onBack, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnClickOutside = false)) {
        val view = LocalView.current
        val window = (view.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.let {
                it.setDimAmount(0f)
                it.setWindowAnimations(0)
                WindowCompat.getInsetsController(it, view).isAppearanceLightStatusBars = true
            }
        }
        content()
    }
}

/** What a sheet's content can do: leave with the sheet's own motion, then run [then] (or the close). */
class SheetScope(val close: (then: (() -> Unit)?) -> Unit)

/**
 * A [DGSheet] in its own layer: it rises on the snap spring, follows the
 * finger between [snaps] (fractions of the screen height, low to high),
 * and slides away on a tap above it, a drag down or Back.
 */
@Composable
fun SheetLayer(
    onClose: () -> Unit,
    snaps: List<Float>,
    modifier: Modifier = Modifier,
    start: Int = 0,
    maxHeight: Dp? = null,
    above: (@Composable SheetScope.() -> Unit)? = null,
    content: @Composable ColumnScope.(SheetScope) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(1f) }
    val leaving = remember { booleanArrayOf(false) }
    val sheetScope = remember {
        SheetScope { then ->
            if (!leaving[0]) {
                leaving[0] = true
                scope.launch { offset.animateTo(1f, tween(260, easing = DG.hideEase)); (then ?: onClose)() }
            }
        }
    }
    LaunchedEffect(Unit) { offset.animateTo(0f, DG.snap()) }
    DGLayer(onBack = { sheetScope.close(null) }) {
        BoxWithConstraints(Modifier.fillMaxSize().imePadding()) {
            val h = this.maxHeight
            val dps = snaps.map { f -> (h * f).let { if (maxHeight != null && it > maxHeight) maxHeight else it } }
            val state = rememberSheetState(dps, start, onDismiss = { sheetScope.close(null) })
            Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) { sheetScope.close(null) })
            above?.invoke(sheetScope)
            DGSheet(state, modifier.align(Alignment.BottomCenter).graphicsLayer { translationY = offset.value * state.height.value }, fill = Color.White.copy(alpha = .55f)) {
                content(sheetScope)
            }
        }
    }
}
