package com.commutescout.drive

import android.app.Activity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.ReportSteps.Step
import com.commutescout.drive.design.*
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Sends a report to commutescout.com, which fans it out to plugins. */
object Reporter {
    suspend fun send(kind: String, lat: Double, lon: Double, heading: Double?, description: String, token: String) {
        val body = buildString {
            append("""{"kind":"$kind","lat":$lat,"lon":$lon,"client":"commutescout-android/${BuildConfig.VERSION_NAME}"""")
            if (heading != null && heading >= 0) append(""","heading_deg":$heading""")
            if (description.isNotBlank()) append(""","description":${JsonPrimitive(description)}""")
            append("}")
        }
        val (status, text) = Backend.send("POST", "/api/flare/report", token, body)
        if (status != 201 && status != 202) {
            val msg = runCatching { Backend.json.parseToJsonElement(text).jsonObject["error"] }.getOrNull()
            val detail = (msg as? JsonPrimitive)?.content ?: (msg as? JsonObject)?.get("message")?.jsonPrimitive?.content
            throw BackendError(if (status == 429) "Too many reports for now. Try again in a minute." else detail ?: "The server refused the report.")
        }
    }

    suspend fun confirm(alertId: String, vote: String, token: String) {
        val (status, _) = Backend.send("POST", "/api/flare/confirm", token, """{"alert_id":${JsonPrimitive(alertId)},"vote":"$vote"}""")
        if (status != 200) throw BackendError("Could not record that.")
    }
}

@kotlinx.serialization.Serializable
data class Snap(val snapped: Boolean = false, val lat: Double, val lon: Double, val road: String? = null, val distance_m: Double = 0.0)

/**
 * Report, like Waze: a tap on a kind, then a five second window to
 * say where on the road, add a note or undo, then it sends on its own.
 */
@Composable
fun ReportSheet(model: DriveViewModel, lat: Double, lon: Double, onClose: () -> Unit) {
    var step by remember { mutableStateOf<Step>(Step.Grid) }
    var picked by remember { mutableStateOf<String?>(null) }
    var where by remember { mutableStateOf(1) }
    var note by remember { mutableStateOf("") }
    // The nearest road within 60 m (the server's /api/snap), unless the
    // driver asks for the exact spot.
    var snap by remember { mutableStateOf<Snap?>(null) }
    var useExact by remember { mutableStateOf(false) }
    LaunchedEffect(lat, lon) {
        snap = runCatching { Backend.get<Snap>("/api/snap", mapOf("lat" to Backend.num(lat, 6), "lon" to Backend.num(lon, 6))) }.getOrNull()
    }
    val placedLat = if (snap?.snapped == true && !useExact) snap!!.lat else lat
    val placedLon = if (snap?.snapped == true && !useExact) snap!!.lon else lon
    val user by model.account.user.collectAsStateWithLifecycle()
    val busy by model.account.busy.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val bound = TripText.bound(model.courseDegrees)
    val road = snap?.road?.takeIf { snap?.snapped == true && !useExact }

    fun send() {
        val s = step
        val id = (s as? Step.Confirm)?.kind ?: (s as? Step.Failed)?.kind ?: return
        val k = ReportKinds.all.first { it.id == id }
        val text = ReportKinds.description(k, where, note)
        // No signal: keep it and send it when there is one. A signed-in
        // driver's token cannot be refreshed offline, and asking them to
        // sign in again would be the wrong answer to a dead zone.
        fun queue() {
            PendingReport.add(PendingReport(k.flare, placedLat, placedLon, model.courseDegrees, text, System.currentTimeMillis()))
            model.toast("No connection. Your report sends when you are back online, if within 15 minutes.")
            onClose()
        }
        step = ReportSteps.send(s)
        scope.launch {
            if (!Connectivity.online.value && user != null) { queue(); return@launch }
            val token = model.account.token()
            if (token == null) {
                step = ReportSteps.failed(step, if (!Connectivity.online.value) OfflineText.RETRY else "Sign in to send reports.")
                if (Connectivity.online.value) (context as? Activity)?.let { model.account.signInWithGoogle(it) }
                return@launch
            }
            try {
                Reporter.send(k.flare, placedLat, placedLon, model.courseDegrees, text, token)
                model.markers.refresh(true)
                step = ReportSteps.sent(step)
            } catch (e: Exception) {
                if (Connectivity.isOffline(e)) queue()
                else step = ReportSteps.failed(step, (e as? BackendError)?.message ?: "Could not send the report. Try again.")
            }
        }
    }

    // Confirm, sending and failed are one page; only grid, confirm and sent swap.
    val page = when (step) { Step.Grid -> 0; is Step.Sent -> 2; else -> 1 }
    FitSheet(Modifier.tag("report-sheet"), onDismiss = onClose, scrim = true) {
        AnimatedContent(page, transitionSpec = { fadeIn(tween(260, 90)) togetherWith fadeOut(tween(140)) }, label = "reportStep") { p ->
            Column {
                when (p) {
                    0 -> {
                        SheetHead("Report", listOfNotNull(road, bound).joinToString(", ").ifEmpty { null }, onClose = onClose)
                        if (user == null) SignInBox(busy) { scope.launch { (context as? Activity)?.let { model.account.signInWithGoogle(it) } } }
                        KindGrid(picked) { k ->
                            picked = k.id
                            // Signed out, the kind stays picked until the driver signs in.
                            if (user != null || ReportDebug.preview) { where = ReportKinds.defaultWhere(k); note = ""; step = ReportSteps.pick(k.id) }
                        }
                        if (snap?.snapped == true) Row(Modifier.fillMaxWidth().padding(start = 22.dp, end = 14.dp, top = 6.dp).tag("report-snap"),
                            verticalAlignment = Alignment.CenterVertically) {
                            Text(if (useExact) "At the exact spot." else "On ${snap?.road ?: "the road"}.", Modifier.weight(1f), style = DGType.small, color = DG.sub)
                            DGButton(if (useExact) "Snap to road" else "Use the exact spot", { useExact = !useExact }, Modifier.tag("report-exact"), style = BtnStyle.QUIET)
                        }
                        Row(Modifier.padding(horizontal = 22.dp, vertical = 12.dp).navigationBarsPadding()) {
                            DGIcon("pin", DG.faint, 15.dp, Modifier.padding(top = 2.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Placed on the road where you are now. Shown to everyone under a pseudonym.", style = PageType.foot, color = DG.faint)
                        }
                    }
                    2 -> {
                        val k = ReportKinds.all.firstOrNull { it.id == (step as? Step.Sent)?.kind }
                        SheetHead("Thanks, it's on the map", listOfNotNull(k?.label, road).joinToString(", ").ifEmpty { null }, lead = { Disc("check", Tone.GOOD) })
                        Text("Drivers coming up behind you can confirm it or say it's gone. It leaves the map once it's cleared.",
                            Modifier.padding(horizontal = 22.dp, vertical = 14.dp), style = DGType.body, color = DG.sub)
                        SheetActions { DGButton("Done", onClose, Modifier.weight(1f).tag("report-done"), style = BtnStyle.PRIMARY) }
                    }
                    else -> {
                        val s = step
                        val id = (s as? Step.Confirm)?.kind ?: (s as? Step.Sending)?.kind ?: (s as? Step.Failed)?.kind
                        ReportKinds.all.firstOrNull { it.id == id }?.let { k ->
                            ConfirmStep(k, bound, road, where, { where = it }, note, { note = it }, s,
                                onUndo = { step = ReportSteps.undo(step); picked = null }, onSend = { send() })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SignInBox(busy: Boolean, onSignIn: () -> Unit) {
    Row(Modifier.padding(start = 14.dp, end = 14.dp, top = 12.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(DG.low.tint(.08f))
        .border(1.dp, DG.low.copy(alpha = .18f), RoundedCornerShape(20.dp)).padding(start = 16.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text("Reports need an account, the same one as the website.", Modifier.weight(1f), style = DGType.small, color = DG.ink)
        Spacer(Modifier.width(8.dp))
        DGButton("Sign in", onSignIn, Modifier.tag("report-sign-in"), style = BtnStyle.BLUE, enabled = !busy)
    }
}

/** Twelve kinds, three across. */
@Composable
private fun KindGrid(picked: String?, onPick: (ReportKinds.Kind) -> Unit) {
    Column(Modifier.padding(start = 14.dp, end = 14.dp, top = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ReportKinds.all.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { k ->
                    val on = picked == k.id
                    val bg by animateColorAsState(if (on) k.tone.color.tint(.12f) else Color.White.copy(alpha = .78f), tween(220), label = "kbg")
                    val edge by animateColorAsState(if (on) k.tone.color.copy(alpha = .5f) else DG.hair, tween(220), label = "ked")
                    val src = remember { MutableInteractionSource() }
                    Column(Modifier.weight(1f).press(src).height(84.dp).clip(RoundedCornerShape(20.dp)).background(bg)
                        .border(if (on) 1.5.dp else 1.dp, edge, RoundedCornerShape(20.dp))
                        .clickable(src, null, role = Role.Button) { onPick(k) }.tag("report-${k.flare}"),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        Disc(k.icon, k.tone, 36.dp)
                        Spacer(Modifier.height(7.dp))
                        Text(k.label, Modifier.padding(horizontal = 4.dp), style = DGType.small.copy(fontWeight = FontWeight.SemiBold), color = DG.ink,
                            textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

/** The road as the driver sees it, with the report where they said. */
internal fun reportSpec(k: ReportKinds.Kind, where: Int?): RoadSpec {
    val hatch = when (k.tone) { Tone.HIGH -> Hatch.HI; Tone.MID -> Hatch.MID; else -> Hatch.LO }
    val w = if (k.asksWhere) where ?: ReportKinds.defaultWhere(k) else 1
    val u = when (w) { 0 -> .5f; 2 -> 4.4f; else -> 3.5f }
    val lane = if (w == 0) 0f else 3f
    return RoadSpec(
        n = 4, k = .62f, sh = .6f, padL = 22f, padR = 22f, scale = 1.25f, you = 2f,
        marks = listOf(RoadSpec.Mark(if (k.asksWhere) u else 2f, .62f, k.icon, hatch)),
        blocks = if (k.lanes && w != 2) listOf(RoadSpec.Block(lane, lane, .5f, .76f, hatch)) else emptyList(),
        cars = if (k.id == "jam") listOf(0 to .5f, 1 to .58f, 1 to .76f, 2 to .66f, 3 to .52f, 3 to .72f) else emptyList(),
        frost = if (k.id == "ice") listOf(.4f to 1f) else emptyList(),
    )
}

@Composable
private fun ConfirmStep(
    k: ReportKinds.Kind, bound: String?, road: String?, where: Int, onWhere: (Int) -> Unit, note: String, onNote: (String) -> Unit,
    step: Step, onUndo: () -> Unit, onSend: () -> Unit,
) {
    val timer = remember { Animatable(0f) }
    var typing by remember { mutableStateOf(false) }
    // Five seconds, then it sends. Choosing a lane starts the count again; typing a note stops it.
    LaunchedEffect(step is Step.Confirm, where, typing) {
        if (step !is Step.Confirm) return@LaunchedEffect
        timer.snapTo(0f)
        if (typing) return@LaunchedEffect
        timer.animateTo(1f, tween(ReportSteps.UNDO_MS.toInt(), easing = LinearEasing))
        onSend()
    }
    SheetHead(ReportKinds.confirmTitle(k, bound), road, lead = { Disc(k.icon, k.tone) })
    Box(Modifier.padding(start = 14.dp, end = 14.dp, top = 14.dp).fillMaxWidth().height(108.dp).clip(RoundedCornerShape(20.dp))
        .background(Color.White).border(1.dp, DG.hair, RoundedCornerShape(20.dp))) {
        LaneDrawing(reportSpec(k, where), DrawKind.CRASH, Modifier.fillMaxSize())
    }
    if (k.asksWhere) Segmented(ReportKinds.WHERE, where, onWhere, Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp), tagPrefix = "report-where")
    Box(Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp).fillMaxWidth().height(46.dp).clip(RoundedCornerShape(23.dp))
        .background(DG.ink.copy(alpha = .055f)).padding(horizontal = 18.dp), contentAlignment = Alignment.CenterStart) {
        if (note.isEmpty()) Text("Add a note (optional)", style = DGType.body, color = DG.faint)
        BasicTextField(note, { onNote(it); typing = true }, Modifier.fillMaxWidth().tag("report-note"),
            textStyle = DGType.body.copy(color = DG.ink), singleLine = true, cursorBrush = SolidColor(DG.low))
    }
    val failed = step as? Step.Failed
    Text(when {
        failed != null -> failed.message
        step is Step.Sending -> "Sending your report."
        typing -> "Tap Send now when your note is ready."
        else -> "Sends on its own in ${ReportSteps.secondsLeft(timer.value)} s, or tap Undo."
    }, Modifier.padding(horizontal = 22.dp, vertical = 12.dp), style = DGType.small, color = if (failed != null) DG.highInk else DG.sub)
    SheetActions {
        DGButton("Undo", onUndo, Modifier.weight(1f).tag("report-undo"), enabled = step !is Step.Sending)
        val src = remember { MutableInteractionSource() }
        Box(Modifier.weight(1.4f).press(src).height(DG.btnH).clip(RoundedCornerShape(24.dp)).background(DG.ink)
            .clickable(src, null, enabled = step !is Step.Sending, role = Role.Button, onClick = onSend).tag("report-send")) {
            // The bar fills as the five seconds run.
            Box(Modifier.fillMaxHeight().fillMaxWidth(when { step is Step.Sending -> 1f; failed != null -> 0f; else -> timer.value }).background(Color.White.copy(alpha = .16f)))
            Text(if (failed != null) "Try again" else if (step is Step.Sending) "Sending" else "Send now", Modifier.align(Alignment.Center),
                style = DGType.button, color = Color.White)
        }
    }
}

/** Debug builds: the confirm step without an account, for screenshots ("csReportPreview"). Sending still asks to sign in. */
object ReportDebug { var preview = false }
