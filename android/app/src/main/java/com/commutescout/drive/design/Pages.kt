package com.commutescout.drive.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/*
 * The building blocks of the full pages (settings, marketplace, watch
 * areas, offline maps): grouped rows, switches, segmented controls,
 * kind chips, tags, facts and the confirm card. Measurements are the
 * round 5 mockups' Android values.
 */

/** Type for pages, on top of [DGType]. */
object PageType {
    private fun s(size: Float, weight: Int, tracking: Float = 0f, line: Float = 1.25f) =
        DGType.row.copy(fontSize = size.sp, fontWeight = FontWeight(weight), letterSpacing = (tracking * size).sp, lineHeight = (size * line).sp)
    val homeTitle = s(28f, 700, -0.025f, 1.1f)
    val navTitle = s(19f, 600)
    val bigTitle = s(30f, 700, -0.025f, 1.1f)
    val intro = s(14.5f, 500, 0f, 1.45f)
    val groupHead = s(14f, 600)
    val foot = s(13f, 500, 0f, 1.45f)
    val note = s(12.5f, 500, 0f, 1.5f)
    val rowLabel = s(16f, 500)
    val rowSub = s(13f, 500, 0f, 1.35f)
    val rowValue = s(15f, 500)
    val chip = s(14.5f, 600)
    val tag = s(12.5f, 600)
    val section = s(17f, 700)
    val stat = s(22f, 700, -0.02f, 1.1f)
    val confirmTitle = s(20f, 700, -0.015f)
    val confirmBody = s(14.5f, 500, 0f, 1.45f)
}

/** The frosted sheet a settings page lives in: full height under the status bar, rounded top. */
@Composable
fun PageSheet(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    Column(
        modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars).padding(top = 6.dp)
            .shadow(24.dp, shape, ambientColor = DG.ink.copy(alpha = .3f), spotColor = DG.ink.copy(alpha = .3f))
            .clip(shape)
            .background(Brush.verticalGradient(listOf(Color(0xF2F8FAFC), Color(0xF2F3F6FA))))
            .border(0.5.dp, DG.edge, shape)
            // Taps on the sheet's background never fall through to the map.
            .clickable(remember { MutableInteractionSource() }, null) {},
    ) {
        Box(Modifier.fillMaxWidth().height(16.dp), contentAlignment = Alignment.Center) { Grab(width = 40.dp) }
        content()
    }
}

/**
 * The page's nav: a back arrow and a left-aligned title, or on the home
 * page a large title with a close button on the right.
 */
@Composable
fun PageNav(title: String, onBack: (() -> Unit)? = null, onClose: (() -> Unit)? = null, home: Boolean = false, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(62.dp).padding(top = 14.dp, bottom = 4.dp, start = if (home) 22.dp else 8.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) NavDisc("backA", "Back", onBack, Modifier.tag("page-back"))
        Text(title, Modifier.weight(1f).padding(start = if (home) 0.dp else 4.dp), style = if (home) PageType.homeTitle else PageType.navTitle,
            color = DG.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (onClose != null) NavDisc("close", "Close", onClose, Modifier.tag("page-close"))
        else if (onBack != null) Spacer(Modifier.width(52.dp))
    }
}

/** A 44 touch target holding a 36 grey disc with an icon: the nav buttons. */
@Composable
fun NavDisc(icon: String, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val src = remember { MutableInteractionSource() }
    Box(modifier.size(44.dp).press(src).clip(CircleShape).clickable(src, null, role = Role.Button, onClick = onClick)
        .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(DG.ink.copy(alpha = .06f)), contentAlignment = Alignment.Center) {
            DGIcon(icon, DG.ink, 20.dp, stroke = 2.2f)
        }
    }
}

/** A group's header: small grey words, an optional colored dot and something on the right. */
@Composable
fun GroupHead(text: String, modifier: Modifier = Modifier, dot: Color? = null, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(start = 24.dp, end = 24.dp, top = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        if (dot != null) { Box(Modifier.size(8.dp).clip(CircleShape).background(dot)); Spacer(Modifier.width(8.dp)) }
        Text(text, Modifier.weight(1f), style = PageType.groupHead, color = DG.sub)
        trailing?.invoke(this)
    }
}

/** Rounded white group that rows sit in. [plugin] tints it purple: plugin settings never look official. */
@Composable
fun Group(modifier: Modifier = Modifier, plugin: Boolean = false, radius: Dp = 22.dp, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier.padding(horizontal = 14.dp).fillMaxWidth()
            .shadow(1.dp, shape, ambientColor = DG.ink.copy(alpha = .04f), spotColor = DG.ink.copy(alpha = .04f))
            .clip(shape)
            .background(if (plugin) Brush.verticalGradient(listOf(DG.plug.tint(.05f), DG.plug.tint(.02f))) else SolidColor(Color(0xD6FFFFFF)))
            .border(1.dp, if (plugin) DG.plug.copy(alpha = .2f) else DG.hair, shape),
        content = content,
    )
}

/** The hairline between two rows, starting at the label when the rows have icons. */
@Composable
fun RowDivider(inset: Dp = 58.dp, plugin: Boolean = false) {
    Box(Modifier.padding(start = inset).fillMaxWidth().height(1.dp).background(if (plugin) DG.plug.copy(alpha = .12f) else DG.hair))
}

/** A group's footnote. */
@Composable
fun GroupFoot(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp), style = PageType.foot, color = DG.sub)
}

/** A rounded-square icon tile in [color]'s gradient, as at the start of a settings row. */
@Composable
fun Tile(icon: String, color: Color, modifier: Modifier = Modifier, size: Dp = 32.dp, iconSize: Dp = 19.dp) {
    Box(modifier.size(size).clip(RoundedCornerShape(size * .31f))
        .background(Brush.verticalGradient(listOf(color.tint(.82f), color))), contentAlignment = Alignment.Center) {
        DGIcon(icon, Color.White, iconSize, stroke = 2.2f)
    }
}

/**
 * One settings row: a tile, a label with an optional line under it,
 * and on the right a value and a chevron, a switch or anything else.
 */
@Composable
fun SRow(
    label: String,
    modifier: Modifier = Modifier,
    icon: String? = null,
    tileColor: Color = DG.low,
    sub: String? = null,
    value: String? = null,
    chevron: Boolean = false,
    labelColor: Color = DG.ink,
    lead: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 54.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(start = if (icon != null || lead != null) 14.dp else 18.dp, end = 14.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (lead != null) { lead(); Spacer(Modifier.width(12.dp)) }
        else if (icon != null) { Tile(icon, tileColor); Spacer(Modifier.width(12.dp)) }
        Column(Modifier.weight(1f)) {
            Text(label, style = PageType.rowLabel, color = labelColor)
            if (sub != null) Text(sub, style = PageType.rowSub, color = DG.sub, modifier = Modifier.padding(top = 1.dp))
        }
        if (value != null) { Spacer(Modifier.width(8.dp)); Text(value, style = PageType.rowValue, color = DG.sub, maxLines = 1) }
        if (trailing != null) { Spacer(Modifier.width(8.dp)); trailing() }
        if (chevron) { Spacer(Modifier.width(6.dp)); DGIcon("chevR", DG.chev, 18.dp, stroke = 2.4f) }
    }
}

/** A row whose whole width toggles its switch. */
@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, icon: String? = null,
              tileColor: Color = DG.low, sub: String? = null, tag: String? = null, enabled: Boolean = true) {
    SRow(label, modifier.then(if (tag != null) Modifier.tag(tag) else Modifier), icon = icon, tileColor = tileColor, sub = sub,
        onClick = if (enabled) ({ onChange(!checked) }) else null) {
        DGSwitch(checked, onChange, enabled = enabled)
    }
}

/** The Android switch, drawn in the design's colors: a ringed grey track off, a blue one on. */
@Composable
fun DGSwitch(checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val track by animateColorAsState(if (checked) DG.low else Color(0xFFE6EAF0), tween(300), label = "sw")
    val thumbSize by animateDpAsState(if (checked) 24.dp else 16.dp, DG.snap(), label = "swt")
    val x by animateDpAsState(if (checked) 24.dp else 8.dp, DG.springy(), label = "swx")
    val thumb by animateColorAsState(if (checked) Color.White else DG.faint, tween(300), label = "swc")
    Box(
        modifier.size(52.dp, 32.dp).clip(CircleShape).background(track)
            .then(if (!checked) Modifier.border(2.dp, DG.faint, CircleShape) else Modifier)
            .clickable(enabled = enabled, role = Role.Switch) { onChange(!checked) }
            .semantics { stateDescription = if (checked) "On" else "Off" },
    ) {
        Box(Modifier.offset(x = x - (thumbSize - 16.dp) / 2, y = (32.dp - thumbSize) / 2).size(thumbSize).clip(CircleShape).background(thumb))
    }
}

/** Segmented control: a white knob that springs to the chosen option. */
@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, icons: List<String>? = null, tagPrefix: String? = null,
              selectedColor: Color = DG.ink) {
    BoxWithConstraints(modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(22.dp)).background(DG.ink.copy(alpha = .055f)).padding(3.dp)) {
        val w = maxWidth / options.size.coerceAtLeast(1)
        val x by animateDpAsState(w * selected.coerceAtLeast(0), DG.snap(), label = "seg")
        if (selected >= 0) Box(Modifier.offset(x = x).width(w).fillMaxHeight()
            .shadow(3.dp, RoundedCornerShape(19.dp), ambientColor = DG.ink.copy(alpha = .25f), spotColor = DG.ink.copy(alpha = .25f))
            .clip(RoundedCornerShape(19.dp)).background(Color.White))
        Row(Modifier.fillMaxSize()) {
            options.forEachIndexed { i, o ->
                val c by animateColorAsState(if (i == selected) selectedColor else DG.sub, tween(300), label = "segc")
                Row(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(19.dp)).clickable(role = Role.Tab) { onSelect(i) }
                    .then(if (tagPrefix != null) Modifier.tag("$tagPrefix-$i") else Modifier),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                    icons?.getOrNull(i)?.let { DGIcon(it, c, 17.dp); Spacer(Modifier.width(6.dp)) }
                    Text(o, style = PageType.chip, color = c, maxLines = 1)
                }
            }
        }
    }
}

/**
 * A kind chip: a colored disc and a label, tinted when on, grey when
 * off, with a check that slides in. Used for alert kinds and watch kinds.
 */
@Composable
fun KindChip(label: String, icon: String, color: Color, on: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    val bg by animateColorAsState(if (on) color.tint(.10f) else Color.White.copy(alpha = .7f), tween(300), label = "kc")
    val edge by animateColorAsState(if (on) color.copy(alpha = .3f) else DG.hair, tween(300), label = "kce")
    val fg by animateColorAsState(if (on) DG.ink else DG.faint, tween(300), label = "kcf")
    val disc by animateColorAsState(if (on) color else DG.ink.copy(alpha = .06f), tween(300), label = "kcd")
    val check by animateDpAsState(if (on) 16.dp else 0.dp, DG.snap(), label = "kck")
    val shape = RoundedCornerShape(22.dp)
    Row(modifier.height(44.dp).clip(shape).background(bg).border(1.dp, edge, shape)
        .clickable(role = Role.Checkbox, onClick = onToggle).semantics { stateDescription = if (on) "On" else "Off" }
        .padding(start = 7.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).clip(CircleShape).background(disc), contentAlignment = Alignment.Center) {
            DGIcon(icon, if (on) Color.White else DG.faint, 17.dp, stroke = 2.2f)
        }
        Spacer(Modifier.width(8.dp))
        Text(label, style = PageType.chip, color = fg, maxLines = 1)
        if (check > 0.5.dp) {
            Spacer(Modifier.width(6.dp))
            Box(Modifier.width(check).clip(RoundedCornerShape(0.dp))) { DGIcon("check", Color(color.red * .8f, color.green * .8f, color.blue * .8f), 16.dp, stroke = 2.6f) }
        }
    }
}

enum class TagLook { PLUGIN, OFFICIAL, GOOD, NEUTRAL, WARN }

/** A small capsule label: "Plugin data", "Official data", "Free", "Live". */
@Composable
fun Tag(text: String, look: TagLook, modifier: Modifier = Modifier, icon: String? = null) {
    val (fg, base) = when (look) {
        TagLook.PLUGIN -> Color(0xFF4A4F9E) to Color(0xFF5B5BD6)
        TagLook.OFFICIAL -> DG.lowInk to DG.low
        TagLook.GOOD -> DG.goodInk to DG.good
        TagLook.WARN -> DG.midInk to DG.mid
        TagLook.NEUTRAL -> DG.sub to DG.ink
    }
    val shape = RoundedCornerShape(13.dp)
    Row(modifier.height(26.dp).clip(shape).background(base.copy(alpha = .09f)).border(1.dp, base.copy(alpha = .2f), shape)
        .padding(start = if (icon != null) 8.dp else 10.dp, end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) { DGIcon(icon, fg, 14.dp, stroke = 2.2f); Spacer(Modifier.width(5.dp)) }
        Text(text, style = PageType.tag, color = fg, maxLines = 1)
    }
}

/** Label and value pairs in a white box, one per line. */
@Composable
fun Facts(rows: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(16.dp)
    Column(modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape).background(Color.White.copy(alpha = .7f)).border(1.dp, DG.hair, shape)) {
        rows.forEachIndexed { i, (k, v) ->
            if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DG.hair))
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp)) {
                Text(k, style = PageType.confirmBody, color = DG.sub, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(16.dp))
                Text(v, style = PageType.confirmBody.copy(fontWeight = FontWeight.SemiBold), color = DG.ink)
            }
        }
    }
}

/** A tinted info box: an icon and a few lines ("Only you see this"). */
@Composable
fun InfoBox(text: String, modifier: Modifier = Modifier, icon: String = "lock", title: String? = null, color: Color = DG.low, titleColor: Color = DG.ink) {
    val shape = RoundedCornerShape(18.dp)
    Row(modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape).background(color.copy(alpha = .07f)).border(1.dp, color.copy(alpha = .14f), shape)
        .padding(horizontal = 14.dp, vertical = 12.dp)) {
        DGIcon(icon, if (color == DG.low) DG.lowInk else color, 20.dp)
        Spacer(Modifier.width(10.dp))
        Column {
            if (title != null) Text(title, style = PageType.rowLabel.copy(fontWeight = FontWeight.SemiBold), color = titleColor)
            Text(text, style = PageType.confirmBody, color = Color(0xFF23406F))
        }
    }
}

/**
 * A confirm card that rises from the bottom over a veil: a question,
 * a line of what happens, and two buttons. Tapping the veil cancels.
 */
@Composable
fun ConfirmCard(visible: Boolean, title: String, body: String?, onDismiss: () -> Unit, modifier: Modifier = Modifier, actions: @Composable RowScope.() -> Unit) {
    Box(modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(tween(250)), exit = fadeOut(tween(200))) {
            Box(Modifier.fillMaxSize().background(DG.ink.copy(alpha = .16f)).clickable(remember { MutableInteractionSource() }, null, onClick = onDismiss))
        }
        AnimatedVisibility(visible, Modifier.align(Alignment.BottomCenter),
            enter = slideInVertically(DG.snap()) { it } + fadeIn(tween(150)),
            exit = slideOutVertically(tween(260, easing = DG.hideEase)) { it } + fadeOut(tween(200))) {
            Column(Modifier.windowInsetsPadding(WindowInsets.navigationBars).padding(start = 10.dp, end = 10.dp, bottom = 6.dp).fillMaxWidth()
                .glass(RoundedCornerShape(30.dp), elevation = 24.dp, strong = true).padding(start = 14.dp, end = 14.dp, top = 20.dp, bottom = 12.dp).tag("confirm-card")) {
                Text(title, Modifier.padding(horizontal = 8.dp), style = PageType.confirmTitle, color = DG.ink)
                if (body != null) Text(body, Modifier.padding(start = 8.dp, end = 8.dp, top = 6.dp), style = PageType.confirmBody, color = DG.sub)
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), content = actions)
            }
        }
    }
}

/** A round glass back button and an optional title, for full-screen pages over the map. */
@Composable
fun TopBar(onBack: () -> Unit, modifier: Modifier = Modifier, title: String? = null, titleAlpha: Float = 1f, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 14.dp, end = 14.dp, top = 6.dp).height(52.dp),
        verticalAlignment = Alignment.CenterVertically) {
        GlassRound("back", "Back", onBack, Modifier.tag("page-back"), size = 44.dp)
        if (title != null) Text(title, Modifier.padding(start = 10.dp).weight(1f).alpha(titleAlpha), style = PageType.navTitle.copy(fontSize = 17.sp), color = DG.ink, maxLines = 1)
        else Spacer(Modifier.weight(1f))
        trailing?.invoke(this)
    }
}

/** A large page title and the line under it. */
@Composable
fun PageTitle(title: String, intro: String? = null, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Text(title, Modifier.padding(horizontal = 24.dp), style = PageType.bigTitle, color = DG.ink)
        if (intro != null) Text(intro, Modifier.padding(start = 24.dp, end = 24.dp, top = 6.dp, bottom = 16.dp), style = PageType.intro, color = DG.sub)
    }
}

/** The dock at the foot of a full page: a fade from the page color and the main buttons. */
@Composable
fun Dock(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(DG.bg.copy(alpha = 0f), DG.bg.copy(alpha = .92f), DG.bg)))
        .windowInsetsPadding(WindowInsets.navigationBars).padding(start = 14.dp, end = 14.dp, top = 22.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

/** A status line in a tinted box: a dot, a bold word and a line under it. */
@Composable
fun StatusBox(title: String, body: String?, good: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(18.dp)
    val c = if (good) DG.good else DG.ink
    Row(modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(shape).background(c.copy(alpha = if (good) .08f else .04f))
        .border(1.dp, if (good) DG.good.copy(alpha = .22f) else DG.hair, shape).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.padding(horizontal = 6.dp).size(10.dp).clip(CircleShape).background(if (good) DG.good else DG.clear))
        Spacer(Modifier.width(6.dp))
        Column {
            Text(title, style = PageType.rowLabel.copy(fontWeight = FontWeight.Bold), color = if (good) DG.goodInk else DG.ink)
            if (body != null) Text(body, style = DGType.meta, color = DG.sub)
        }
    }
}

/** A text field in the design: a small label over the value, in a white rounded box. */
@Composable
fun DGField(label: String, value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = "", tag: String? = null) {
    val shape = RoundedCornerShape(18.dp)
    val style = PageType.rowLabel.copy(fontSize = 16.5.sp, fontWeight = FontWeight.SemiBold)
    Column(modifier.padding(horizontal = 14.dp).fillMaxWidth().heightIn(min = 56.dp).clip(shape).background(Color.White.copy(alpha = .8f)).border(1.dp, DG.hair, shape)
        .padding(horizontal = 16.dp, vertical = 6.dp), verticalArrangement = Arrangement.Center) {
        Text(label, style = PageType.note, color = DG.sub)
        Box {
            if (value.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, style = style, color = DG.faint)
            BasicTextField(value, onChange, Modifier.fillMaxWidth().then(if (tag != null) Modifier.tag(tag) else Modifier),
                textStyle = style.copy(color = DG.ink), singleLine = true, cursorBrush = SolidColor(DG.low))
        }
    }
}
