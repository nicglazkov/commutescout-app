package com.commutescout.drive

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.BtnStyle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.DGButton
import com.commutescout.drive.design.DGIcon
import com.commutescout.drive.design.DGLayer
import com.commutescout.drive.design.DGSwitch
import com.commutescout.drive.design.DGType
import com.commutescout.drive.design.Disc
import com.commutescout.drive.design.GlassRound
import com.commutescout.drive.design.Group
import com.commutescout.drive.design.InfoBox
import com.commutescout.drive.design.PageTitle
import com.commutescout.drive.design.PageType
import com.commutescout.drive.design.RowDivider
import com.commutescout.drive.design.SRow
import com.commutescout.drive.design.Segmented
import com.commutescout.drive.design.SheetLayer
import com.commutescout.drive.design.Tag
import com.commutescout.drive.design.TagLook
import com.commutescout.drive.design.Tile
import com.commutescout.drive.design.Tone
import com.commutescout.drive.design.TopBar
import com.commutescout.drive.design.glass
import com.commutescout.drive.design.press
import com.commutescout.drive.design.tag
import com.commutescout.drive.design.tint
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A plugin's badge: a rounded square in its own color. Official alerts are round; plugins never are. */
@Composable
fun PluginTile(s: FlareSource, size: Dp = 52.dp) {
    val c = PluginStyle.color(s.id)
    Tile(Market.glyph(s.kinds), c, Modifier.shadow(size * .12f, RoundedCornerShape(size * .31f), ambientColor = c, spotColor = c), size = size, iconSize = size / 2)
}

/** The data tag: official data (a shield, green) or plugin data (a piece, indigo). */
@Composable
private fun DataTag(s: FlareSource) {
    if (Market.data(s) == Market.Data.OFFICIAL) Tag("Official data", TagLook.GOOD, icon = "shield")
    else Tag("Plugin data", TagLook.PLUGIN, icon = "piece")
}

/**
 * The marketplace: a full page over the veiled map. A filter by where
 * the data comes from, a card per listed plugin with Add, and a tap on
 * a card opens its page.
 */
@Composable
fun MarketplaceSheet(model: DriveViewModel, onClose: () -> Unit) {
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val hidden by model.sources.hidden.collectAsStateWithLifecycle()
    val paused by model.sources.paused.collectAsStateWithLifecycle()
    var filter by remember { mutableStateOf(Market.Filter.ALL) }
    var detailsOf by remember { mutableStateOf<String?>(null) }
    var listFailed by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val shown = remember { Animatable(0f) }
    var leaving by remember { mutableStateOf(false) }
    fun close() { if (!leaving) { leaving = true; scope.launch { shown.animateTo(0f, tween(220, easing = DG.hideEase)); onClose() } } }
    LaunchedEffect(Unit) { listFailed = !model.sources.loadCatalog() }
    LaunchedEffect(Unit) { shown.animateTo(1f, DG.soft()) }

    DGLayer(onBack = ::close) {
        // While a plugin's page is up, the market steps aside so its map shows.
        val away by animateFloatAsState(if (detailsOf != null) 0f else 1f, tween(320), label = "away")
        val list = Market.filter(catalog, filter)
        val added = list.count { Market.isAdded(it.id, hidden, paused) }
        val listState = rememberLazyListState()
        val stuck by remember { derivedStateOf { listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset > 60 } }
        val d = LocalDensity.current
        Box(Modifier.fillMaxSize().alpha(shown.value.coerceIn(0f, 1f) * away).tag("marketplace-sheet")) {
            Box(Modifier.fillMaxSize().background(Color(0xFFECF1F6)).clickable(remember { MutableInteractionSource() }, null) {})
            val top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
            val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
            LazyColumn(Modifier.fillMaxSize().graphicsLayer { translationY = (1f - shown.value) * with(d) { 24.dp.toPx() } }, listState,
                contentPadding = PaddingValues(top = top + 58.dp, bottom = bottom + 24.dp)) {
                item(key = "title") {
                    PageTitle("Marketplace", "Plugins add alerts and places to your map. Everything they show follows your account and no one else's.")
                }
                item(key = "filter") {
                    Segmented(Market.Filter.entries.map { it.label }, filter.ordinal, { filter = Market.Filter.entries[it] },
                        Modifier.padding(horizontal = 14.dp).glass(RoundedCornerShape(24.dp), elevation = 8.dp), tagPrefix = "market-filter", selectedColor = DG.lowInk)
                }
                item(key = "count") {
                    Text(if (catalog.isEmpty()) Market.emptyLine(listFailed) else Market.countLine(list.size, added),
                        Modifier.padding(start = 24.dp, end = 24.dp, top = 22.dp, bottom = 8.dp).tag("market-count"), style = PageType.groupHead, color = DG.sub)
                }
                itemsIndexed(list, key = { _, s -> "${filter.name}:${s.id}" }) { i, s ->
                    PluginCard(s, Market.isAdded(s.id, hidden, paused), i, onOpen = { detailsOf = s.id }) { on ->
                        if (on) model.sources.addPlugin(s.id) else model.sources.removePlugin(s.id)
                        model.markers.refresh(true)
                    }
                    Spacer(Modifier.height(10.dp))
                }
                item(key = "note") {
                    Text("Official data comes from public agencies and is packaged by CommuteScout. Plugin data comes from the plugin's maker; reviewed plugins say so on their page.",
                        Modifier.padding(start = 24.dp, end = 24.dp, top = 6.dp), style = PageType.note, color = DG.faint)
                    Text("Write a plugin", Modifier.padding(start = 14.dp, top = 4.dp).clip(RoundedCornerShape(12.dp))
                        .clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://commutescout.com/plugins"))) }
                        .padding(horizontal = 10.dp, vertical = 10.dp), style = PageType.foot.copy(fontWeight = FontWeight.SemiBold), color = DG.lowInk)
                }
            }
            // The bar: the round back button, and the title once the big one has scrolled away.
            val barAlpha by animateFloatAsState(if (stuck) 1f else 0f, tween(250), label = "bar")
            Box(Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color(0xF5F0F4F8), Color(0xD1F0F4F8), Color(0x00F0F4F8))))
                .padding(bottom = 10.dp)) {
                TopBar(::close, title = "Marketplace", titleAlpha = barAlpha)
            }
        }
        detailsOf?.let { PluginStatusSheet(model, it) { detailsOf = null } }
    }
}

/** One marketplace card. */
@Composable
private fun PluginCard(s: FlareSource, added: Boolean, index: Int, onOpen: () -> Unit, onToggle: (Boolean) -> Unit) {
    // Cards settle in one after another, as they do when the filter changes.
    val enter = remember { Animatable(0f) }
    LaunchedEffect(Unit) { delay(80L + 50L * index.coerceAtMost(8)); enter.animateTo(1f, DG.springy()) }
    val d = LocalDensity.current
    val shape = RoundedCornerShape(24.dp)
    Box(Modifier.padding(horizontal = 14.dp).fillMaxWidth()
        .graphicsLayer { alpha = enter.value.coerceIn(0f, 1f); translationY = (1f - enter.value) * with(d) { 18.dp.toPx() } }
        .glass(shape, elevation = 10.dp).tag("plugin-card")) {
        Column(Modifier.fillMaxWidth().clickable(onClickLabel = "Open ${s.name}", onClick = onOpen).tag("status-${s.id}")
            .padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PluginTile(s)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(s.name, style = PageType.rowLabel.copy(fontSize = 16.5.sp, fontWeight = FontWeight.SemiBold), color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(Market.maker(s), style = PageType.rowSub, color = DG.sub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
                }
                Spacer(Modifier.width(8.dp))
                AddPill(added, s.name, Modifier.tag("install-${s.id}")) { onToggle(!added) }
            }
            Text(Market.purpose(s), Modifier.padding(start = 2.dp, end = 2.dp, top = 10.dp), style = PageType.intro.copy(lineHeight = 20.5.sp), color = DG.ink,
                maxLines = 4, overflow = TextOverflow.Ellipsis)
            Row(Modifier.padding(top = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                DataTag(s)
                Spacer(Modifier.weight(1f))
                Text(s.coverageLabel, style = PageType.note, color = DG.faint, maxLines = 1)
            }
        }
    }
}

/** Add, blue; Added, green with a check. It springs when it changes. */
@Composable
private fun AddPill(added: Boolean, name: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val src = remember { MutableInteractionSource() }
    val bg by animateColorAsState(if (added) DG.good.copy(alpha = .10f) else DG.low, tween(300), label = "add")
    val fg by animateColorAsState(if (added) DG.goodInk else Color.White, tween(300), label = "addf")
    val pop = remember { Animatable(1f) }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(added) { if (first) first = false else { pop.snapTo(.9f); pop.animateTo(1f, DG.springy()) } }
    val shape = RoundedCornerShape(19.dp)
    Row(modifier.press(src).graphicsLayer { scaleX = pop.value; scaleY = pop.value }
        .then(if (added) Modifier else Modifier.shadow(6.dp, shape, ambientColor = DG.low, spotColor = DG.low))
        .height(38.dp).clip(shape).background(bg)
        .then(if (added) Modifier.border(1.dp, DG.good.copy(alpha = .28f), shape) else Modifier)
        .clickable(src, null, role = Role.Button, onClick = onClick)
        .semantics { contentDescription = (if (added) "Added " else "Add ") + name }
        .padding(horizontal = if (added) 14.dp else 18.dp), verticalAlignment = Alignment.CenterVertically) {
        if (added) { DGIcon("check", fg, 16.dp, stroke = 2.8f); Spacer(Modifier.width(6.dp)) }
        Text(if (added) "Added" else "Add", style = PageType.chip, color = fg)
    }
}

/**
 * One plugin's page, the one place for everything about it: whether it
 * is on the map, what it adds and can use, whether it is answering (with
 * a check now), and Remove, which asks first in place.
 */
@Composable
fun PluginStatusSheet(model: DriveViewModel, sourceId: String, onClose: () -> Unit) {
    val catalog by model.sources.catalog.collectAsStateWithLifecycle()
    val mine by model.sources.mine.collectAsStateWithLifecycle()
    val hidden by model.sources.hidden.collectAsStateWithLifecycle()
    val paused by model.sources.paused.collectAsStateWithLifecycle()
    val direct by model.sources.directMarkers.collectAsStateWithLifecycle()
    val live = catalog.firstOrNull { it.id == sourceId } ?: mine.firstOrNull { it.id == sourceId }
    // A private plugin is gone from the list once removed; its page stays until closed.
    var last by remember { mutableStateOf<FlareSource?>(null) }
    if (live != null && live != last) last = live
    val s = live ?: last
    var checking by remember { mutableStateOf(false) }
    var checkedAt by remember { mutableStateOf<Long?>(null) }
    var reach by remember { mutableStateOf<String?>(null) }
    var step by remember { mutableStateOf(Market.RemoveStep.IDLE) }
    val scope = rememberCoroutineScope()

    SheetLayer(onClose, snaps = listOf(.70f, .91f), modifier = Modifier.tag("plugin-status"),
        above = {
            // The map chrome steps back behind a soft wash, as in the design.
            Box(Modifier.fillMaxWidth().background(Brush.verticalGradient(0f to Color(0xF5F0F4F8), .72f to Color(0xF5F0F4F8), 1f to Color(0x00F0F4F8))).padding(bottom = 76.dp)) {
                TopBar({ close(null) })
            }
        }) { sheet ->
        if (s == null) {
            Text("This plugin is no longer listed.", Modifier.padding(24.dp), style = DGType.body, color = DG.sub)
            return@SheetLayer
        }
        val added = Market.isAdded(s.id, hidden, paused) && step != Market.RemoveStep.REMOVED
        val on = s.id !in hidden
        val count = if (s.base != null) direct.count { it.id?.startsWith("${s.id}:") == true }.takeIf { it > 0 } ?: s.count else s.count
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = 2.dp, bottom = 24.dp)) {
            Row(Modifier.padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                PluginTile(s, 56.dp)
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(s.name, style = DGType.sheetTitle, color = DG.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(Market.maker(s), style = PageType.intro, color = DG.sub, modifier = Modifier.padding(top = 3.dp))
                }
            }
            Row(Modifier.padding(start = 18.dp, end = 18.dp, top = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                DataTag(s)
                if (s.tier == "approved") Tag("Reviewed", TagLook.GOOD, icon = "check")
                else if (s.tier == "private") Tag("Private", TagLook.NEUTRAL, icon = "lock")
                else Tag("Not reviewed", TagLook.WARN)
                Tag(s.coverageLabel.takeIf { it != "Coverage not stated" } ?: "Coverage not stated", TagLook.NEUTRAL)
            }
            if (added) {
                Spacer(Modifier.height(16.dp))
                Group {
                    SRow("Show on my map", Modifier.padding(vertical = 2.dp), sub = Market.showSub(on), onClick = { model.sources.setShown(s.id, !on); model.markers.refresh(true) }) {
                        DGSwitch(on, { v -> model.sources.setShown(s.id, v); model.markers.refresh(true) }, Modifier.tag("plugin-installed"))
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            InfoBox("What this plugin shows follows the account that added it. It never reaches anyone else, and it never sees who else uses it.",
                icon = "lock", title = "Only you see this", titleColor = DG.lowInk)

            Section("What it adds")
            Group {
                SRow("On the map", sub = Market.purpose(s), lead = { SoftTile("map") })
                RowDivider()
                SRow("In alerts", sub = Market.inAlerts(s), lead = { SoftTile("bell") })
                RowDivider()
                SRow("Its marker", sub = "Plugins are rounded squares. Official alerts are round.", lead = { SoftTile("eye") }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Tile(Market.glyph(s.kinds), PluginStyle.color(s.id), Modifier.border(2.dp, Color.White, RoundedCornerShape(9.dp)), size = 28.dp, iconSize = 15.dp)
                        Spacer(Modifier.width(10.dp))
                        Disc("crash", Tone.HIGH, 28.dp, modifier = Modifier.border(2.dp, Color.White, CircleShape))
                    }
                }
            }

            Section("What it can use")
            Group {
                Market.uses(s).forEachIndexed { i, u ->
                    if (i > 0) RowDivider(inset = 54.dp)
                    SRow(u.title, sub = u.sub, lead = {
                        Box(Modifier.size(30.dp).clip(CircleShape).background(if (u.allowed) DG.good.copy(alpha = .10f) else DG.ink.copy(alpha = .05f)), contentAlignment = Alignment.Center) {
                            DGIcon(if (u.allowed) "check" else "nope", if (u.allowed) DG.goodInk else DG.sub, 16.dp, stroke = if (u.allowed) 2.8f else 2.4f)
                        }
                    })
                }
            }

            Section("Status")
            val (answer, good) = Market.answering(s, System.currentTimeMillis())
            val facts = buildList {
                add(Triple("Answering", answer, when (good) { true -> DG.goodInk; false -> DG.highInk; null -> DG.sub }))
                add(Triple("On your map now", if (on) Market.alertsNow(count) else "Not shown", DG.ink))
                if (s.ok == false) s.lastError?.let { add(Triple("Last error", it, DG.highInk)) }
                if (s.ok == false) s.lastOk?.let { add(Triple("Last good answer", Market.ago(it, System.currentTimeMillis()), DG.ink)) }
                if (s.fails > 0) add(Triple("Failures in a row", "${s.fails}", DG.ink))
                reach?.let { add(Triple("Reached from this phone", it, DG.ink)) }
                add(Triple("Checks for new data", Market.every(s.refreshS), DG.ink))
                s.version?.let { add(Triple("Version", it, DG.ink)) }
                s.contact?.let { add(Triple("Contact", it, DG.ink)) }
            }
            StatusFacts(facts)
            Row(Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                DGButton(if (checking) "Checking" else "Check now", {
                    checking = true
                    scope.launch {
                        model.sources.loadCatalog()
                        s.base?.let { base ->
                            val t0 = System.currentTimeMillis()
                            reach = runCatching {
                                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                    Backend.http.newCall(okhttp3.Request.Builder().url("$base/flare/v1/handshake").build()).execute().use { r ->
                                        if (r.isSuccessful) "Yes, ${System.currentTimeMillis() - t0} ms" else "Answered ${r.code}"
                                    }
                                }
                            }.getOrDefault("No")
                        }
                        checkedAt = System.currentTimeMillis()
                        checking = false
                    }
                }, Modifier.tag("plugin-check"), icon = "refresh", enabled = !checking)
                checkedAt?.let {
                    Text("Checked " + java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(it)),
                        Modifier.padding(start = 12.dp), style = PageType.note, color = DG.sub)
                }
            }
            Text(Market.footnote(s), Modifier.padding(start = 18.dp, end = 18.dp, top = 12.dp), style = PageType.note, color = DG.faint)
        }
        // The actions bar: Remove asks first, in place.
        Row(Modifier.fillMaxWidth().background(Color.White.copy(alpha = .6f)).drawBehind { drawLine(DG.hair, Offset(0f, 0f), Offset(size.width, 0f), 1.dp.toPx()) }
            .windowInsetsPadding(WindowInsets.navigationBars).padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                step == Market.RemoveStep.REMOVED -> DGButton("Removed", {}, Modifier.weight(1f).tag("plugin-removed"), style = BtnStyle.DONE, icon = "check")
                step == Market.RemoveStep.CONFIRM -> {
                    DGButton("Keep it", { step = Market.RemoveStep.IDLE }, Modifier.weight(1f).tag("plugin-keep"))
                    DGButton("Remove", {
                        model.sources.removePlugin(s.id); model.markers.refresh(true)
                        step = Market.RemoveStep.REMOVED
                    }, Modifier.weight(1f).tag("plugin-remove-yes"), style = BtnStyle.DANGER_SOLID)
                }
                added -> DGButton("Remove plugin", { step = Market.RemoveStep.CONFIRM }, Modifier.weight(1f).tag("plugin-remove"), style = BtnStyle.DANGER, icon = "trash")
                else -> DGButton("Add plugin", { model.sources.addPlugin(s.id); model.markers.refresh(true) }, Modifier.weight(1f).tag("plugin-add"), style = BtnStyle.BLUE, icon = "plus")
            }
        }
    }
}

/** A row's soft blue icon square, as in the design's detail rows. */
@Composable
private fun SoftTile(icon: String) {
    Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(DG.low.copy(alpha = .10f)), contentAlignment = Alignment.Center) {
        DGIcon(icon, DG.low, 19.dp, stroke = 2.1f)
    }
}

@Composable
private fun Section(text: String) {
    Text(text, Modifier.padding(start = 18.dp, end = 18.dp, top = 20.dp, bottom = 8.dp), style = PageType.section, color = DG.ink)
}

/** Label and value pairs, the value in its own color. */
@Composable
private fun StatusFacts(rows: List<Triple<String, String, Color>>) {
    val shape = RoundedCornerShape(16.dp)
    Column(Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape).background(Color.White.copy(alpha = .7f)).border(1.dp, DG.hair, shape)) {
        rows.forEachIndexed { i, (k, v, c) ->
            if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DG.hair))
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp)) {
                Text(k, style = PageType.confirmBody, color = DG.sub, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(16.dp))
                Text(v, Modifier.weight(1.3f), style = PageType.confirmBody.copy(fontWeight = FontWeight.SemiBold), color = c, textAlign = TextAlign.End)
            }
        }
    }
}
