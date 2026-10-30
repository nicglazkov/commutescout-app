package com.commutescout.drive

import android.app.Activity
import android.app.TimePickerDialog
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.layout.RowScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGSwitch
import com.commutescout.drive.design.Dock
import com.commutescout.drive.design.GroupHead
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.PageTitle
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.TopBar
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.tag
import com.stadiamaps.ferrostar.maplibreui.runtime.NavigationMapState
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import java.time.ZoneId

/** The account's watch areas over the network; null token or no signal answers (0, ""). */
object WatchApi {
    @Serializable private data class Limits(val free_watches: Int? = null)
    @Serializable private data class Config(val limits: Limits? = null)

    /** How many watch areas an account keeps (the backend's free limit). */
    suspend fun limit(): Int = runCatching { Backend.get<Config>("/api/watch/config", emptyMap()).limits?.free_watches }.getOrNull() ?: 3

    suspend fun call(model: DriveViewModel, method: String, path: String, body: String? = null): Pair<Int, String> {
        val token = model.account.token() ?: return 401 to ""
        return runCatching { Backend.send(method, path, token, body) }.getOrElse { 0 to "" }
    }

    suspend fun me(model: DriveViewModel): MeResponse? {
        val (status, text) = call(model, "GET", "/api/watch/me")
        return if (status == 200) runCatching { Backend.json.decodeFromString<MeResponse>(text) }.getOrNull() else null
    }
}

/** Debug builds can open these pages with made-up data, signed out (MainActivity's csPage and csFixtures). */
object MorePages {
    var fixtures = false
    /** watches, watchedit, offline, picker or savedmap: opened once the map is up. */
    var wanted by mutableStateOf<String?>(null)
    var offlineOpen by mutableStateOf(false)

    val fixtureWatches: List<Watch> by lazy {
        fun pts(vararg p: Pair<Double, Double>) = kotlinx.serialization.json.buildJsonArray {
            p.forEach { (a, b) -> add(kotlinx.serialization.json.buildJsonObject { put("lat", kotlinx.serialization.json.JsonPrimitive(a)); put("lon", kotlinx.serialization.json.JsonPrimitive(b)) }) }
        }
        val now = java.time.Instant.now()
        listOf(
            Watch("f1", "Home area", "circle", Watch.Center(37.442, -122.143), 12.87, listOf("incident", "closure", "fire"), true,
                live = Watch.Live(0, quiet_since = now.minusSeconds(3 * 3600).toString())),
            Watch("f2", "Work commute", "route", points = pts(37.442 to -122.143, 37.43 to -122.11, 37.40 to -122.08, 37.39 to -122.03),
                buffer_km = 3.2, length_km = 14.0, kinds = listOf("incident", "closure"), active = true,
                live = Watch.Live(1, mapOf("incident" to 1), Watch.Top("incident", "1 crash now", ""))),
            Watch("f3", "Ski route", "route", points = pts(39.74 to -104.99, 39.70 to -105.2, 39.68 to -105.7, 39.64 to -106.37),
                buffer_km = 3.2, length_km = 156.0, kinds = listOf("chain", "incident"), active = true,
                live = Watch.Live(1, mapOf("chain" to 1), Watch.Top("chain", "Chains required on I-70", ""))),
        )
    }
    val fixturePrefs = WatchPrefs(alerts_push = true, alerts_email = false, notify_clears = true,
        quiet_hours = QuietHours(true, "22:00", "06:00", "America/Los_Angeles", true))
}

/** The rounded light-blue icon tile at the start of a page row. */
@Composable
fun RowTile(icon: String, modifier: Modifier = Modifier, color: Color = DG.low) {
    Box(modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(color.copy(alpha = .1f)), contentAlignment = Alignment.Center) {
        DGIcon(icon, color, 19.dp, stroke = 2.1f)
    }
}

/** A full page over a veiled map: the veil, a scrolling column, a back button that stays put and a dock. */
@Composable
fun MapPage(title: String, onBack: () -> Unit, modifier: Modifier = Modifier, dock: (@Composable RowScope.() -> Unit)? = null,
            content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val scroll = rememberScrollState()
    val stuck by animateFloatAsState(if (scroll.value > 40) 1f else 0f, tween(300), label = "stuck")
    Box(modifier.fillMaxSize().background(Color(0xFFECF1F6).copy(alpha = .985f))
        .clickable(remember { MutableInteractionSource() }, null) {}) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).windowInsetsPadding(WindowInsets.statusBars).padding(top = 58.dp)) {
            content()
            Spacer(Modifier.height(if (dock != null) 110.dp else 28.dp))
            Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars))
        }
        Box(Modifier.fillMaxWidth().drawBehind {
            drawRect(Brush.verticalGradient(listOf(Color(0xFFF0F4F8).copy(alpha = .96f), Color(0xFFF0F4F8).copy(alpha = .82f + .14f * stuck),
                Color(0xFFF0F4F8).copy(alpha = stuck * .96f))))
        }) {
            TopBar(onBack, title = null, trailing = null)
            Text(title, Modifier.align(Alignment.CenterStart).windowInsetsPadding(WindowInsets.statusBars).padding(start = 68.dp, top = 6.dp)
                .graphicsLayer { alpha = stuck }, style = PageType.navTitle.copy(fontSize = 17.sp), color = DG.ink)
        }
        if (dock != null) Box(Modifier.align(Alignment.BottomCenter)) { Dock(content = dock) }
    }
}

/**
 * Watch areas: the account's areas with what is happening in each,
 * how alerts reach the person, and New watch area, which opens the
 * editor over the map. Reached from Tools.
 */
@Composable
fun WatchesSheet(model: DriveViewModel, mapState: NavigationMapState, onClose: () -> Unit) {
    val user by model.account.user.collectAsStateWithLifecycle()
    val fixtures = BuildConfig.DEBUG && MorePages.fixtures
    val signedIn = user != null || fixtures
    var me by remember { mutableStateOf(if (fixtures) MeResponse(prefs = MorePages.fixturePrefs, watches = MorePages.fixtureWatches) else null) }
    var limit by remember { mutableIntStateOf(3) }
    var loading by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Watch?>(null) }
    var creating by remember { mutableStateOf(MorePages.wanted == "watchedit") }
    var quietOpen by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    suspend fun load() {
        if (fixtures || user == null) return
        loading = true
        WatchApi.me(model)?.let { me = it } ?: run { if (me == null) message = if (Connectivity.online.value) "Could not load your watch areas." else OfflineText.RETRY }
        loading = false
    }
    LaunchedEffect(user) { load(); limit = WatchApi.limit() }
    LaunchedEffect(Unit) { if (MorePages.wanted == "watchedit") MorePages.wanted = null }

    val watches = me?.watches.orEmpty()
    val prefs = me?.prefs ?: WatchPrefs()
    val pushOn = (prefs.alerts_push ?: true) && (watches.isEmpty() || watches.any { it.channels?.push != false })
    val emailOn = if (watches.isEmpty()) prefs.alerts_email == true else (prefs.alerts_email ?: true) && watches.any { it.channels?.email == true }

    /** Saves account prefs; the switch moves at once and moves back if the server says no. */
    fun savePrefs(next: WatchPrefs, body: String, patch: (suspend () -> Unit)? = null) {
        val before = me
        me = (me ?: MeResponse()).copy(prefs = next)
        if (fixtures) return
        scope.launch {
            val (status, text) = WatchApi.call(model, "POST", "/api/watch/prefs", body)
            if (status != 200) { me = before; message = WatchBodies.error(status, text); return@launch }
            runCatching { Backend.json.decodeFromString<PrefsResponse>(text).prefs }.getOrNull()?.let { p -> me = me?.copy(prefs = p) }
            patch?.invoke()
        }
    }
    fun patchChannels(push: Boolean?, email: Boolean?) = suspend {
        for (w in watches) {
            val p = push ?: (w.channels?.push != false); val e = email ?: (w.channels?.email == true)
            if (p != (w.channels?.push != false) || e != (w.channels?.email == true)) WatchApi.call(model, "PATCH", "/api/watch/${w.id}", WatchBodies.channels(p, e))
        }
        load()
    }

    val inEditor = creating || editing != null
    BackHandler { if (quietOpen) quietOpen = false else if (inEditor) { creating = false; editing = null } else onClose() }
    Box(Modifier.fillMaxSize().tag("watches-sheet")) {
        Crossfade(inEditor, animationSpec = tween(320), label = "watch-editor") { edit ->
            if (edit) {
                WatchEditor(model, mapState, editing, prefs, pushOn, emailOn, fixtures,
                    onSaved = { scope.launch { load() } },
                    onClose = { creating = false; editing = null })
            } else MapPage("Watch areas", onClose, dock = if (signedIn) ({
                val full = watches.size >= limit
                DGButton(if (full) "$limit of $limit watch areas in use" else "New watch area", { creating = true },
                    Modifier.weight(1f).tag("watch-new"), style = BtnStyle.PRIMARY, icon = if (full) null else "plus", enabled = !full)
            }) else null) {
                PageTitle("Watch areas", "Get an alert when something happens inside an area or along a drive, anywhere in the US.")
                if (!signedIn) {
                    SignInCard { scope.launch { (context as? Activity)?.let { model.account.signInWithGoogle(it) } } }
                    return@MapPage
                }
                if (loading && me == null) Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = DG.low) }
                if (me != null && watches.isEmpty()) Text("None yet. A watch area alerts you about what happens inside it, even when the app is closed.",
                    Modifier.padding(horizontal = 24.dp, vertical = 4.dp), style = PageType.foot, color = DG.sub)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    watches.forEach { w -> WatchCard(w, model) { editing = w } }
                }
                GroupHead("How you hear about it")
                Group {
                    SRow("Notifications", Modifier.tag("watch-push"), sub = "On this phone and your others", lead = { RowTile("bell") },
                        onClick = { val on = !pushOn; savePrefs(prefs.copy(alerts_push = on), WatchBodies.prefs(push = on), if (on) patchChannels(true, null) else null) }) {
                        DGSwitch(pushOn, { on -> savePrefs(prefs.copy(alerts_push = on), WatchBodies.prefs(push = on), if (on) patchChannels(true, null) else null) })
                    }
                    RowDivider()
                    SRow("Email", Modifier.tag("watch-email"), sub = "To the address on your account", lead = { RowTile("mail") },
                        onClick = { val on = !emailOn; savePrefs(prefs.copy(alerts_email = on), WatchBodies.prefs(email = on), if (on) patchChannels(null, true) else null) }) {
                        DGSwitch(emailOn, { on -> savePrefs(prefs.copy(alerts_email = on), WatchBodies.prefs(email = on), if (on) patchChannels(null, true) else null) })
                    }
                    RowDivider()
                    val clears = prefs.notify_clears == true
                    SRow("Tell me when it clears", Modifier.tag("watch-clears"), sub = "A short follow-up once it's over", lead = { RowTile("check") },
                        onClick = { savePrefs(prefs.copy(notify_clears = !clears), WatchBodies.prefs(clears = !clears)) }) {
                        DGSwitch(clears, { savePrefs(prefs.copy(notify_clears = it), WatchBodies.prefs(clears = it)) })
                    }
                    RowDivider()
                    SRow("Quiet hours", Modifier.tag("watch-quiet"), sub = WatchText.quietLine(prefs.quiet_hours), lead = { RowTile("moon") },
                        chevron = true, onClick = { quietOpen = true })
                }
                message?.let { Text(it, Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = PageType.note, color = DG.highInk) }
                Text("Your account can keep $limit watch areas. Each one alerts at most once per event.",
                    Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = PageType.note, color = DG.faint)
            }
        }
        QuietHoursCard(quietOpen, prefs.quiet_hours ?: QuietHours(tz = ZoneId.systemDefault().id), onDismiss = { quietOpen = false }) { q ->
            quietOpen = false
            savePrefs(prefs.copy(quiet_hours = q), WatchBodies.prefs(quiet = q))
        }
    }
}

@Composable
private fun SignInCard(onSignIn: () -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().glass(RoundedCornerShape(24.dp), elevation = 14.dp).padding(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            RowTile("watch"); Spacer(Modifier.width(12.dp))
            Text("Sign in to keep watch areas", style = DGTypeRow, color = DG.ink)
        }
        Text("Watch areas follow your account, so alerts reach this phone, your others and your email. It's the same account as the website.",
            Modifier.padding(top = 10.dp), style = PageType.confirmBody, color = DG.sub)
        Spacer(Modifier.height(14.dp))
        DGButton("Sign in with Google", onSignIn, Modifier.fillMaxWidth().tag("watch-sign-in"), style = BtnStyle.PRIMARY)
    }
}

private val DGTypeRow = PageType.rowLabel.copy(fontSize = 16.5.sp, fontWeight = FontWeight.SemiBold)

/** One watch area: its thumb, name, what is happening there now and what it covers. */
@Composable
private fun WatchCard(w: Watch, model: DriveViewModel, onOpen: () -> Unit) {
    val status = WatchText.status(w)
    val home = Engine.places.home?.let { LatLon(it.lat, it.lon) }; val work = Engine.places.work?.let { LatLon(it.lat, it.lon) }
    val src = remember { MutableInteractionSource() }
    Row(Modifier.padding(horizontal = 14.dp).fillMaxWidth().heightIn(min = 88.dp).glass(RoundedCornerShape(24.dp), elevation = 14.dp)
        .clickable(src, null, onClick = onOpen).padding(start = 10.dp, end = 12.dp, top = 10.dp, bottom = 10.dp).tag("watch-${w.id}"),
        verticalAlignment = Alignment.CenterVertically) {
        MiniMap(when (w.shape) { "route" -> Mini.ROUTE; "polygon" -> Mini.SHAPE; else -> Mini.CIRCLE }, path = w.path,
            dot = status?.takeIf { it.live }?.tone?.color)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(w.name ?: "Watch area", style = DGTypeRow.copy(lineHeight = 20.sp), color = DG.ink, maxLines = 1)
            if (status != null) Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                LiveDot(status.tone.color, status.live)
                Spacer(Modifier.width(7.dp))
                Text(status.text, style = PageType.rowSub.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold), color = status.tone.ink, maxLines = 1)
            }
            Text(WatchText.meta(w, home, work), Modifier.padding(top = 2.dp), style = PageType.rowSub, color = DG.sub, maxLines = 1)
        }
        DGIcon("next", DG.faint, 20.dp, stroke = 2.2f)
    }
}

/** The status dot; while something is happening it sends out a ring every 1.8 s. */
@Composable
private fun LiveDot(color: Color, live: Boolean) {
    val t = if (live) rememberInfiniteTransition(label = "live").animateFloat(0f, 1f, infiniteRepeatable(tween(1800), RepeatMode.Restart), label = "ring").value else 0f
    Box(Modifier.size(8.dp).drawBehind {
        if (live) drawCircle(color.copy(alpha = .5f * (1 - t)), radius = size.minDimension / 2 + 8.dp.toPx() * t)
        drawCircle(color)
    })
}

/** Quiet hours for the whole account: on or off, from and to, and the one summary after. */
@Composable
private fun QuietHoursCard(visible: Boolean, current: QuietHours, onDismiss: () -> Unit, onSave: (QuietHours) -> Unit) {
    var q by remember(visible) { mutableStateOf(current) }
    val context = LocalContext.current
    fun pick(start: Boolean) {
        val (h, m) = (if (start) q.start else q.end).split(":").map { it.toIntOrNull() ?: 0 }
        TimePickerDialog(context, { _, hh, mm ->
            val v = "%02d:%02d".format(hh, mm)
            q = if (start) q.copy(start = v) else q.copy(end = v)
        }, h, m, android.text.format.DateFormat.is24HourFormat(context)).show()
    }
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(tween(250)), exit = fadeOut(tween(200))) {
            Box(Modifier.fillMaxSize().background(DG.ink.copy(alpha = .16f)).clickable(remember { MutableInteractionSource() }, null, onClick = onDismiss))
        }
        AnimatedVisibility(visible, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(DG.snap()) { it } + fadeIn(tween(150)),
            exit = slideOutVertically(tween(260, easing = DG.hideEase)) { it } + fadeOut(tween(200))) {
            Column(Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(start = 10.dp, end = 10.dp, bottom = 6.dp).fillMaxWidth()
                .glass(RoundedCornerShape(30.dp), elevation = 24.dp, strong = true).padding(top = 18.dp, bottom = 12.dp).tag("quiet-card")) {
                Text("Quiet hours", Modifier.padding(horizontal = 22.dp), style = PageType.confirmTitle, color = DG.ink)
                Text("Alerts that come in during these hours wait. Watch areas can opt out one by one.",
                    Modifier.padding(start = 22.dp, end = 22.dp, top = 4.dp, bottom = 12.dp), style = PageType.confirmBody, color = DG.sub)
                Group {
                    SRow("Quiet hours", onClick = { q = q.copy(enabled = !q.enabled) }) { DGSwitch(q.enabled, { q = q.copy(enabled = it) }) }
                    RowDivider(18.dp)
                    SRow("Starts", value = WatchText.time(q.start), chevron = true, onClick = { pick(true) })
                    RowDivider(18.dp)
                    SRow("Ends", value = WatchText.time(q.end), chevron = true, onClick = { pick(false) })
                    RowDivider(18.dp)
                    SRow("Then one summary", sub = "What waited, in one alert when they end", onClick = { q = q.copy(summary = !q.summary) }) {
                        DGSwitch(q.summary, { q = q.copy(summary = it) })
                    }
                }
                Spacer(Modifier.height(14.dp))
                Row(Modifier.padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DGButton("Cancel", onDismiss, Modifier.weight(1f))
                    DGButton("Save", { onSave(q.copy(tz = ZoneId.systemDefault().id)) }, Modifier.weight(1f).tag("quiet-save"), style = BtnStyle.PRIMARY,
                        enabled = q.start != q.end)
                }
            }
        }
    }
}
