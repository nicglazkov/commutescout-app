package com.commutescout.drive

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.Tile
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.tag
import com.commutescout.drive.design.tint
import com.commutescout.drive.design.veil
import kotlinx.coroutines.launch

/** Launch options a debug build reads from its intent extras. */
object DebugLaunch {
    /** A Settings page to open on launch: `--es csSettings units`. */
    @Volatile var settings: String? = null
    fun takeSettings(): String? = settings.also { settings = null }
}

/**
 * The first-run steps, as data so their order and copy are tested
 * without a phone: what each says, what it asks for, and its buttons.
 */
object WelcomeSteps {
    enum class Ask { LOCATION, NOTIFICATIONS, SIGN_IN }
    data class Step(val title: String, val body: String, val ask: Ask, val askTitle: String?, val askBody: String?, val yes: String, val no: String)

    val steps = listOf(
        Step("Know the road before you drive it", "Live crashes, closures, weather and more from official sources, on any route in the US.",
            Ask.LOCATION, "Use your location while you use the app", "To show what is ahead on your route. It is never shared or sold.",
            "Allow while using", "Not now"),
        Step("Hear about your watch areas", "Get a notification when something happens near home, work or any area you watch, even when the app is closed.",
            Ask.NOTIFICATIONS, "Allow notifications", "Only for watch areas and trips you start. You can change this anytime.",
            "Allow notifications", "Not now"),
        Step("Sign in, if you like", "Driving works without an account. Signing in adds:", Ask.SIGN_IN, null, null, "Sign in", "Start driving"),
    )
    val perks = listOf("report" to "Reports from the road", "devices" to "Watch areas everywhere", "puzzle" to "Plugins", "key" to "API keys")

    fun label(index: Int) = "Step ${index + 1} of ${steps.size}"
    /** The step after [index], or null when the last one is done. */
    fun next(index: Int): Int? = (index + 1).takeIf { it < steps.size }
}

/**
 * The first-run screen, over the map: three steps that ask for location,
 * then notifications, then offer sign-in. Every ask can be skipped, and
 * each yes makes the system's own request. Shown once, on the first
 * launch; a debug build can show it again from Settings > Testing.
 */
@Composable
fun WelcomeScreen(model: DriveViewModel, onDone: () -> Unit) {
    var step by remember { mutableIntStateOf(0) }
    var forward by remember { mutableStateOf(true) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun advance() { val n = WelcomeSteps.next(step); if (n == null) onDone() else { forward = true; step = n } }
    val location = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        model.setLocationPermission(granted[Manifest.permission.ACCESS_FINE_LOCATION] == true || granted[Manifest.permission.ACCESS_COARSE_LOCATION] == true)
        advance()
    }
    val notify = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { advance() }
    BackHandler(enabled = step > 0) { forward = false; step -= 1 }
    fun yes() {
        when (WelcomeSteps.steps[step].ask) {
            WelcomeSteps.Ask.LOCATION -> location.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
            WelcomeSteps.Ask.NOTIFICATIONS -> if (Build.VERSION.SDK_INT >= 33) notify.launch(Manifest.permission.POST_NOTIFICATIONS) else advance()
            WelcomeSteps.Ask.SIGN_IN -> scope.launch {
                (context as? android.app.Activity)?.let { model.account.signInWithGoogle(it) }
                onDone()
            }
        }
    }

    Box(Modifier.fillMaxSize().veil(soft = true).clickable(remember { MutableInteractionSource() }, null) {}.tag("welcome")) {
        // The name at the top, and on step 2 a sample of what a watch notification looks like.
        Column(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.statusBars).padding(top = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.glass(CircleShape, elevation = 14.dp).padding(start = 8.dp, end = 22.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(40.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(DG.lowTop, DG.low))), contentAlignment = Alignment.Center) {
                    DGIcon("nav", Color.White, 20.dp, stroke = 2.4f)
                }
                Spacer(Modifier.width(12.dp))
                Text("CommuteScout", style = DGType.title, color = DG.ink)
            }
            AnimatedVisibility(step == 1, enter = slideInVertically(DG.snap()) { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut()) {
                Row(Modifier.padding(horizontal = 14.dp, vertical = 14.dp).fillMaxWidth().glass(RoundedCornerShape(24.dp), strong = true)
                    .padding(14.dp).tag("welcome-sample"), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(40.dp).clip(CircleShape).background(DG.high), contentAlignment = Alignment.Center) { DGIcon("crash", Color.White, 22.dp) }
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("Home area: crash on US-101", style = DGType.row, color = DG.ink)
                        Text("Right lane blocked at University Ave", style = DGType.meta, color = DG.sub)
                    }
                    Text("now", style = DGType.meta, color = DG.faint)
                }
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(10.dp).fillMaxWidth()
            .glass(RoundedCornerShape(30.dp), elevation = 24.dp, strong = true).padding(start = 14.dp, end = 14.dp, top = 18.dp, bottom = 14.dp)) {
            Row(Modifier.padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                WelcomeSteps.steps.indices.forEach { i ->
                    val on by animateFloatAsState(if (i <= step) 1f else 0f, tween(300), label = "bar")
                    Box(Modifier.weight(1f).height(4.dp).clip(CircleShape).background(DG.ink.copy(alpha = .08f))) {
                        Box(Modifier.fillMaxWidth(on).height(4.dp).clip(CircleShape).background(DG.low))
                    }
                    Spacer(Modifier.width(6.dp))
                }
                Spacer(Modifier.width(8.dp))
                Text(WelcomeSteps.label(step), style = PageType.note.copy(fontWeight = FontWeight.SemiBold), color = DG.sub)
            }
            AnimatedContent(step, label = "welcome-step", transitionSpec = {
                val d = if (forward) 1 else -1
                (slideInHorizontally(tween(420, 120, DG.easeOut)) { d * 90 } + fadeIn(tween(420, 120))) togetherWith
                    (slideOutHorizontally(tween(200)) { -d * 90 } + fadeOut(tween(200)))
            }) { i ->
                val s = WelcomeSteps.steps[i]
                Column {
                    Text(s.title, Modifier.padding(start = 8.dp, end = 8.dp, top = 16.dp), style = PageType.bigTitle.copy(fontSize = PageType.homeTitle.fontSize), color = DG.ink)
                    Text(s.body, Modifier.padding(start = 8.dp, end = 8.dp, top = 8.dp), style = PageType.intro, color = DG.sub)
                    Spacer(Modifier.height(14.dp))
                    if (s.ask == WelcomeSteps.Ask.SIGN_IN) Perks()
                    else Ask(if (s.ask == WelcomeSteps.Ask.LOCATION) "nav" else "bell", s.askTitle!!, s.askBody!!)
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DGButton(s.yes, { yes() }, Modifier.weight(1.4f).tag("welcome-yes"), style = BtnStyle.PRIMARY)
                        DGButton(s.no, { if (s.ask == WelcomeSteps.Ask.SIGN_IN) onDone() else advance() }, Modifier.weight(1f).tag("welcome-no"))
                    }
                }
            }
        }
    }
}

@Composable
private fun Ask(icon: String, title: String, body: String) {
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.fillMaxWidth().clip(shape).background(DG.low.tint(.08f)).border(1.dp, DG.low.copy(alpha = .16f), shape).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(DG.lowTop, DG.low))), contentAlignment = Alignment.Center) {
            DGIcon(icon, Color.White, 22.dp, stroke = 2.3f)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, style = PageType.rowLabel.copy(fontWeight = FontWeight.Bold), color = DG.ink)
            Text(body, style = PageType.rowSub, color = Color(0xFF23406F))
        }
    }
}

@Composable
private fun Perks() {
    val colors = listOf(DG.low, Color(0xFF12A39A), DG.plug, DG.mid)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        WelcomeSteps.perks.chunked(2).forEachIndexed { r, row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEachIndexed { c, (icon, label) ->
                    val shape = RoundedCornerShape(18.dp)
                    Row(Modifier.weight(1f).clip(shape).background(Color.White.copy(alpha = .75f)).border(1.dp, DG.hair, shape).padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Tile(icon, colors[r * 2 + c], size = 30.dp, iconSize = 17.dp)
                        Spacer(Modifier.width(10.dp))
                        Text(label, style = PageType.rowSub.copy(fontWeight = FontWeight.SemiBold), color = DG.ink)
                    }
                }
            }
        }
    }
}
