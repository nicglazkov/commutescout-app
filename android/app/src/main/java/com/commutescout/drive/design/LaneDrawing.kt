package com.commutescout.drive.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.commutescout.drive.LaneLayout
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/*
 * The lane drawings: a stretch of road in light perspective, u across
 * the lanes (0 at the left edge, n at the right), v along the road (0
 * where you are, 1 the far end). A port of the design's road() so the
 * thumbnail, the large drawing and the catalog all agree.
 */

/** A hatch color: the stripe and its background. */
enum class Hatch(val stripe: Color, val back: Color) {
    HI(Color(0xFFE5484D), Color(0xFFFDE6E6)),
    MID(Color(0xFFEE8B0C), Color(0xFFFDF0DC)),
    LO(Color(0xFF2F7CF6), Color(0xFFE4EEFE)),
    OK(Color(0xFF14A35A), Color(0xFFE1F4E9)),
    ICE(Color(0xFF4F95D6), Color(0xFFE3EFFA)),
}

/** What to draw on the road. Every distance is the design's px, drawn as dp. */
data class RoadSpec(
    val n: Int = 4,
    val k: Float = .56f,
    val sh: Float = .32f,
    val padT: Float = 8f, val padB: Float = 10f, val padL: Float = 8f, val padR: Float = 8f,
    val scale: Float = 1f,
    val surface: Color = Color.White,
    val lanesFill: Color = DG.laneFill,
    val tint: List<Pair<Int, Hatch>> = emptyList(),
    val frost: List<Pair<Float, Float>> = emptyList(),
    val blocks: List<Block> = emptyList(),
    val cars: List<Pair<Int, Float>> = emptyList(),
    val across: List<Pair<Float, Hatch>> = emptyList(),
    val path: LanePath? = null,
    val pathW: Float = 4f,
    val marks: List<Mark> = emptyList(),
    val you: Float? = null,
    val ticks: List<Tick> = emptyList(),
) {
    /** Lanes [l0] to [l1] inclusive (0-based; -1 and n are the shoulders), from [from] to [to] along the road. */
    data class Block(val l0: Float, val l1: Float, val from: Float, val to: Float, val tone: Hatch = Hatch.HI, val taper: Float = 0f, val left: Boolean = false, val ghost: Boolean = false)
    data class LanePath(val from: Float, val to: Float, val m0: Float = .25f, val m1: Float = .55f, val v0: Float = .07f, val v1: Float = .86f)
    data class Mark(val u: Float, val v: Float, val icon: String, val tone: Hatch, val r: Float = 11f)
    data class Tick(val v: Float, val text: String, val strong: Boolean = false)
}

private val PATH_BLUE = Color(0xFF2F7CF6)

/** Draws [spec] filling the scope. [progress] runs the merge arrow from 0 (not drawn) to 1. */
fun DrawScope.drawRoad(spec: RoadSpec, progress: Float = 1f, text: TextMeasurer? = null) {
    val w = size.width / density
    val h = size.height / density
    val o = spec
    val n = o.n.toFloat()
    val c = (1 - o.k) * 1.15f
    fun g(v: Float) = v * (1 + c) / (1 + c * v)
    val wb = w - o.padL - o.padR
    val ub = wb / (n + 2 * o.sh)
    val cx = o.padL + wb / 2
    fun sAt(v: Float) = 1 - (1 - o.k) * g(v)
    fun p(u: Float, v: Float) = Offset(cx + (u - n / 2) * ub * sAt(v), h - o.padB - g(v) * (h - o.padT - o.padB))
    fun poly(a: Offset, b: Offset, c: Offset, d: Offset) = Path().apply { moveTo(a.x, a.y); lineTo(b.x, b.y); lineTo(c.x, c.y); lineTo(d.x, d.y); close() }
    fun quad(u0: Float, u1: Float, v0: Float, v1: Float) = poly(p(u0, v0), p(u1, v0), p(u1, v1), p(u0, v1))
    val s = o.scale

    fun hatchFill(path: Path, t: Hatch, alpha: Float = 1f) {
        drawPath(path, t.back.copy(alpha = alpha))
        clipPath(path) {
            val step = 6f * s
            val big = (w + h) * 2
            rotate(45f, Offset(w / 2, h / 2)) {
                var x = -big
                while (x < big) {
                    drawRect(t.stripe.copy(alpha = .75f * alpha), Offset(w / 2 + x, h / 2 - big), Size(2.2f * s, big * 2))
                    x += step
                }
            }
        }
    }

    val dens = density
    withTransform({ scale(dens, dens, Offset.Zero) }) {
        drawPath(quad(-o.sh, n + o.sh, 0f, 1f), o.surface)
        drawPath(quad(0f, n, 0f, 1f), o.lanesFill)
        for ((lane, t) in o.tint) drawPath(quad(lane.toFloat(), lane + 1f, 0f, 1f), t.back)
        for ((f0, f1) in o.frost) hatchFill(quad(0f, n, f0, f1), Hatch.ICE, .9f)
        drawLine(Color.White, p(0f, 0f), p(0f, 1f), 1.8f * s)
        drawLine(Color.White, p(n, 0f), p(n, 1f), 1.8f * s)
        for (i in 1 until o.n) {
            var v = 0f
            while (v < 1f) {
                drawLine(Color.White, p(i.toFloat(), v), p(i.toFloat(), min(1f, v + .05f)), 1.6f * s, StrokeCap.Round)
                v += .1f
            }
        }
        for ((lane, v) in o.cars) {
            val pt = p(lane + .5f, v); val sv = sAt(v); val cw = ub * sv * .34f; val chh = ub * sv * .5f
            drawRoundRect(DG.mid.copy(alpha = .8f), Offset(pt.x - cw / 2, pt.y - chh / 2), Size(cw, chh), androidx.compose.ui.geometry.CornerRadius(cw / 3))
        }
        for (b in o.blocks) {
            val l0 = b.l0; val l1 = b.l1 + 1; val t = b.taper
            val path = when {
                t == 0f -> poly(p(l0, b.from), p(l1, b.from), p(l1, b.to), p(l0, b.to))
                b.left -> poly(p(l1, b.from), p(l0, b.from - t), p(l0, b.to), p(l1, b.to))
                else -> poly(p(l0, b.from), p(l1, b.from - t), p(l1, b.to), p(l0, b.to))
            }
            if (b.ghost) drawPath(path, Hatch.OK.stripe.copy(alpha = .6f),
                style = Stroke(1.4f * s, join = StrokeJoin.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f * s, 3f * s))))
            else {
                hatchFill(path, b.tone)
                drawPath(path, b.tone.stripe.copy(alpha = .55f), style = Stroke(1f * s, join = StrokeJoin.Round))
            }
        }
        for ((v, t) in o.across) drawLine(t.stripe, p(-o.sh, v), p(n + o.sh, v), 3f * s,
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f * s, 3f * s)))
        o.path?.let { lp ->
            fun sm(x: Float) = if (x <= 0) 0f else if (x >= 1) 1f else x * x * (3 - 2 * x)
            val pts = ArrayList<Offset>()
            var v = lp.v0
            while (v <= lp.v1 + 1e-4f) { pts.add(p(lp.from + .5f + (lp.to - lp.from) * sm((v - lp.m0) / (lp.m1 - lp.m0)), v)); v += .015f }
            if (pts.size >= 3 && progress > 0f) {
                val full = Path().apply { moveTo(pts[0].x, pts[0].y); for (i in 1 until pts.size) lineTo(pts[i].x, pts[i].y) }
                val lw = o.pathW * s
                drawPath(full, PATH_BLUE.copy(alpha = .14f), style = Stroke(ub * o.k * .78f, cap = StrokeCap.Round, join = StrokeJoin.Round))
                val drawn = if (progress >= 1f) full else Path().also { out ->
                    val pm = PathMeasure(); pm.setPath(full, false); pm.getSegment(0f, pm.length * progress, out, true)
                }
                drawPath(drawn, PATH_BLUE, style = Stroke(lw, cap = StrokeCap.Round, join = StrokeJoin.Round))
                val headA = ((progress - .7f) / .3f).coerceIn(0f, 1f)
                if (headA > 0f) {
                    val e = pts.last(); val q = pts[pts.size - 3]
                    val ang = atan2(e.y - q.y, e.x - q.x); val hs = lw * 2.2f
                    val tip = Offset(e.x + cos(ang) * hs * .6f, e.y + sin(ang) * hs * .6f)
                    val perp = ang + Math.PI.toFloat() / 2
                    val l = Offset(tip.x - cos(ang) * hs * 1.5f + cos(perp) * hs, tip.y - sin(ang) * hs * 1.5f + sin(perp) * hs)
                    val r = Offset(tip.x - cos(ang) * hs * 1.5f - cos(perp) * hs, tip.y - sin(ang) * hs * 1.5f - sin(perp) * hs)
                    val head = Path().apply { moveTo(l.x, l.y); lineTo(tip.x, tip.y); lineTo(r.x, r.y) }
                    drawPath(head, PATH_BLUE.copy(alpha = headA), style = Stroke(lw, cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
            }
        }
        for (m in o.marks) {
            val pt = p(m.u, m.v); val sv = max(.62f, sAt(m.v)); val r = m.r * s * sv
            drawCircle(Color.White, r, pt)
            drawCircle(m.tone.stripe, r, pt, style = Stroke(1.6f * s))
            val icon = r * 1.25f
            translate(pt.x - icon / 2, pt.y - icon / 2) {
                scale(icon / 24f, icon / 24f, Offset.Zero) {
                    for (sp in DGIcons.strokes(m.icon)) drawPath(sp, m.tone.stripe, style = Stroke(2.3f, cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
            }
        }
        o.you?.let { you ->
            val pt = p(you + .5f, .02f); val z = 6.5f * s
            val arrow = Path().apply {
                moveTo(pt.x, pt.y - z * 1.5f); lineTo(pt.x + z, pt.y + z * .9f); lineTo(pt.x, pt.y + z * .35f); lineTo(pt.x - z, pt.y + z * .9f); close()
            }
            drawPath(arrow, PATH_BLUE)
            drawPath(arrow, Color.White, style = Stroke(1.8f * s, join = StrokeJoin.Round))
        }
        if (text != null) for (t in o.ticks) {
            val pt = p(-o.sh, t.v)
            drawLine(Color(0xFFAAB3BE), Offset(pt.x - 5, pt.y), Offset(pt.x + 1, pt.y), 1.2f)
            val style = TextStyle(fontFamily = Onest, fontSize = 12.sp, fontWeight = if (t.strong) FontWeight(650) else FontWeight.Medium,
                color = if (t.strong) DG.ink else Color(0xFF6B7684))
            val lay = text.measure(t.text, style)
            // The text measurer works in px; undo the dp scale for it.
            scale(1 / density, 1 / density, Offset(pt.x - 9, pt.y)) {
                drawText(lay, topLeft = Offset(pt.x - 9 - lay.size.width, pt.y - lay.size.height / 2f))
            }
        }
    }
    // The far end fades into the card: 0 at the top to full at 13%.
    drawRect(Brush.verticalGradient(0f to Color.Transparent, .13f to Color.Black), blendMode = BlendMode.DstIn)
}

/** A small map for a fire: the route, a red glow off to the side, and the fire. */
fun DrawScope.drawFireMap() {
    val w = size.width / density; val h = size.height / density
    val dens = density
    withTransform({ scale(dens, dens, Offset.Zero) }) {
        val x = w * .36f
        val route = Path().apply { moveTo(x, h + 2); cubicTo(x - 4, h * .6f, x + 6, h * .4f, x, -2f) }
        drawPath(route, Color.White, style = Stroke(7f, cap = StrokeCap.Round))
        drawPath(route, PATH_BLUE, style = Stroke(3f, cap = StrokeCap.Round))
        val c = Offset(w * .74f, h * .45f); val r = h * .4f
        drawCircle(Brush.radialGradient(0f to DG.high.copy(alpha = .45f), .7f to DG.high.copy(alpha = .16f), 1f to Color.Transparent, center = c, radius = r), r, c)
        translate(c.x - 7.5f, c.y - 7.5f) { scale(15f / 24f, 15f / 24f, Offset.Zero) {
            for (sp in DGIcons.strokes("fire")) drawPath(sp, DG.high, style = Stroke(2.2f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        } }
        drawCircle(PATH_BLUE, 4f, Offset(x, h * .82f)); drawCircle(Color.White, 4f, Offset(x, h * .82f), style = Stroke(1.8f))
    }
}

/** A message board on two posts, its lines in amber. */
fun DrawScope.drawBoard() {
    val w = size.width / density; val h = size.height / density
    val dens = density
    withTransform({ scale(dens, dens, Offset.Zero) }) {
        val bw = w * .8f; val bh = h * .5f; val x = (w - bw) / 2; val y = h * .14f
        drawRect(Color(0xFFB9C2CC), Offset(w / 2 - 10, y + bh), Size(2.5f, h - y - bh))
        drawRect(Color(0xFFB9C2CC), Offset(w / 2 + 7.5f, y + bh), Size(2.5f, h - y - bh))
        drawRoundRect(Color(0xFF26303C), Offset(x, y), Size(bw, bh), androidx.compose.ui.geometry.CornerRadius(4f))
        drawRoundRect(Color(0xFFF3C66B), Offset(x + bw * .12f, y + bh * .28f), Size(bw * .76f, 2.4f), androidx.compose.ui.geometry.CornerRadius(1.2f))
        drawRoundRect(Color(0xFFF3C66B), Offset(x + bw * .12f, y + bh * .62f), Size(bw * .5f, 2.4f), androidx.compose.ui.geometry.CornerRadius(1.2f))
    }
}

/**
 * The drawing for one alert kind (see [DrawKind]), its lanes from the
 * event's [layout] when the server sent one. Without a layout the kind
 * drawing says nothing about which lane: no blocked lane, no merge.
 */
object Drawings {
    /** The catalog drawing for [kind], exactly as the design draws it. */
    fun catalog(kind: DrawKind): RoadSpec = when (kind) {
        DrawKind.CRASH -> RoadSpec(blocks = listOf(RoadSpec.Block(3f, 3f, .62f, .88f)), marks = listOf(RoadSpec.Mark(3.5f, .75f, "crash", Hatch.HI)),
            you = 3f, path = RoadSpec.LanePath(3f, 2f, .18f, .5f))
        DrawKind.CLOSURE -> RoadSpec(blocks = listOf(RoadSpec.Block(2f, 3f, .55f, 1.05f, taper = .16f)), marks = listOf(RoadSpec.Mark(3f, .76f, "closure", Hatch.HI)),
            you = 3f, path = RoadSpec.LanePath(3f, 1f, .12f, .42f))
        DrawKind.HAZARD -> RoadSpec(marks = listOf(RoadSpec.Mark(.5f, .66f, "hazard", Hatch.MID)), blocks = listOf(RoadSpec.Block(0f, 0f, .6f, .72f, Hatch.MID)),
            you = 0f, path = RoadSpec.LanePath(0f, 1f, .16f, .48f))
        DrawKind.POLICE -> RoadSpec(sh = .7f, marks = listOf(RoadSpec.Mark(4.35f, .66f, "police", Hatch.LO)), you = 3f, path = RoadSpec.LanePath(3f, 2f, .2f, .5f))
        DrawKind.JAM -> RoadSpec(cars = listOf(0 to .5f, 0 to .7f, 1 to .44f, 1 to .64f, 1 to .84f, 2 to .52f, 2 to .72f, 3 to .46f, 3 to .66f, 3 to .86f),
            you = 2f, path = RoadSpec.LanePath(2f, 2f, v1 = .36f))
        DrawKind.CHAIN -> RoadSpec(across = listOf(.6f to Hatch.HI), marks = listOf(RoadSpec.Mark(2f, .76f, "chain", Hatch.HI)), surface = Color(0xFFF4F7FA),
            you = 2f, path = RoadSpec.LanePath(2f, 2f, v1 = .5f))
        DrawKind.ICE -> RoadSpec(frost = listOf(.45f to 1f), marks = listOf(RoadSpec.Mark(2f, .7f, "ice", Hatch.MID)), you = 1f, path = RoadSpec.LanePath(1f, 1f))
        DrawKind.CAMERA -> RoadSpec(sh = .7f, marks = listOf(RoadSpec.Mark(4.35f, .62f, "camera", Hatch.LO)), you = 2f, path = RoadSpec.LanePath(2f, 2f))
        DrawKind.TOLL -> RoadSpec(tint = listOf(0 to Hatch.LO), marks = listOf(RoadSpec.Mark(.5f, .66f, "toll", Hatch.LO)), you = 1f, path = RoadSpec.LanePath(1f, 1f))
        DrawKind.FIRE, DrawKind.SIGN -> RoadSpec()
    }

    private fun markFor(kind: DrawKind): Pair<String, Hatch> = when (kind) {
        DrawKind.CRASH -> "crash" to Hatch.HI
        DrawKind.CLOSURE -> "closure" to Hatch.HI
        DrawKind.HAZARD -> "hazard" to Hatch.MID
        DrawKind.POLICE -> "police" to Hatch.LO
        DrawKind.JAM -> "traffic" to Hatch.MID
        DrawKind.CHAIN -> "chain" to Hatch.HI
        DrawKind.ICE -> "ice" to Hatch.MID
        DrawKind.CAMERA -> "camera" to Hatch.LO
        DrawKind.TOLL -> "toll" to Hatch.LO
        DrawKind.FIRE -> "fire" to Hatch.HI
        DrawKind.SIGN -> "sign" to Hatch.LO
    }

    /**
     * The drawing for an alert of [kind]. With a [layout] the lanes are
     * the event's: its count, its closed lanes and shoulders, and a merge
     * arrow to the target. Without one, the kind drawing with no lane
     * picked out. [near] runs 0 (far off) to 1 (on it) and slides the
     * event toward you.
     */
    fun forAlert(kind: DrawKind, layout: LaneLayout?, near: Float = 0f): RoadSpec {
        val base = catalog(kind)
        val slide = near.coerceIn(0f, 1f) * .42f
        if (layout == null) {
            // Keep what the kind looks like, drop every claim about a lane.
            val lane = when (kind) { DrawKind.TOLL, DrawKind.JAM, DrawKind.ICE, DrawKind.CHAIN, DrawKind.CAMERA, DrawKind.POLICE -> null; else -> 2f }
            return if (lane == null) base else base.copy(
                blocks = emptyList(), you = 1.5f, path = RoadSpec.LanePath(1.5f, 1.5f),
                marks = base.marks.map { it.copy(u = 2f, v = it.v - slide) },
            )
        }
        val n = layout.total
        val (icon, tone) = markFor(kind)
        val closed = layout.closedLanes.map { it - 1 }
        val vFrom = .5f - slide; val vTo = .8f - slide
        val blocks = ArrayList<RoadSpec.Block>()
        // Runs of closed lanes become one block each.
        var i = 0
        while (i < closed.size) {
            var j = i
            while (j + 1 < closed.size && closed[j + 1] == closed[j] + 1) j++
            blocks.add(RoadSpec.Block(closed[i].toFloat(), closed[j].toFloat(), vFrom, vTo, if (tone == Hatch.LO) Hatch.HI else tone))
            i = j + 1
        }
        val sh = if (layout.shoulderLeft == false || layout.shoulderRight == false) .7f else .32f
        if (layout.shoulderLeft == false) blocks.add(RoadSpec.Block(-sh, -1f, vFrom, vTo, Hatch.MID))
        if (layout.shoulderRight == false) blocks.add(RoadSpec.Block(n.toFloat(), n + sh - 1f, vFrom, vTo, Hatch.MID))
        val markU = when {
            closed.isNotEmpty() -> (closed.first() + closed.last() + 1) / 2f
            layout.shoulderRight == false -> n + sh / 2
            layout.shoulderLeft == false -> -sh / 2
            else -> n / 2f
        }
        val merge = layout.merge
        val you = merge?.first?.minus(1)?.toFloat() ?: (layout.target?.minus(1)?.toFloat()) ?: ((n - 1) / 2f)
        val path = if (merge != null) RoadSpec.LanePath(you, merge.second - 1f, .18f - slide * .7f, max(.22f, .5f - slide)) else RoadSpec.LanePath(you, you)
        return base.copy(n = n, sh = sh, blocks = if (kind == DrawKind.CLOSURE && blocks.isNotEmpty()) blocks.map { it.copy(taper = .12f) } else blocks,
            marks = listOf(RoadSpec.Mark(markU, (vFrom + vTo) / 2, icon, if (tone == Hatch.LO && closed.isNotEmpty()) Hatch.HI else tone)),
            you = you, path = path, cars = if (kind == DrawKind.JAM) base.cars.filter { it.first < n } else emptyList(),
            tint = emptyList(), frost = base.frost, across = base.across)
    }

    /** A cleared event: green lanes, the event a dashed ghost, a check where it was. */
    fun cleared(layout: LaneLayout?): RoadSpec {
        val n = layout?.total ?: 4
        val l = (layout?.closedLanes?.firstOrNull()?.minus(1) ?: (n - 1)).toFloat()
        return RoadSpec(n = n, padT = 4f, padB = 6f, lanesFill = Color(0xFFDCEFE3), blocks = listOf(RoadSpec.Block(l, l, .5f, .8f, ghost = true)),
            marks = listOf(RoadSpec.Mark(l + .5f, .65f, "check", Hatch.OK)), you = l, path = RoadSpec.LanePath(l, l))
    }

    /** The large drawing in "see more": the event sits closer as the distance runs down. */
    fun large(kind: DrawKind, layout: LaneLayout?, miles: Double, ticks: List<RoadSpec.Tick>): RoadSpec {
        val vc = (.28f + .46f * min(1.0, miles / .8).toFloat())
        val base = forAlert(kind, layout)
        return base.copy(k = .74f, sh = min(base.sh, .5f).coerceAtLeast(.3f), padL = 58f, padR = 22f, padT = 12f, padB = 18f, pathW = 5f, scale = 1.35f,
            blocks = base.blocks.map { it.copy(from = vc - .12f, to = vc + .13f) },
            marks = base.marks.map { it.copy(v = vc, r = 12f) },
            path = base.path?.let { if (it.from != it.to) it.copy(m0 = .1f, m1 = max(.2f, vc - .2f), v1 = .95f) else it.copy(v1 = .95f) }, ticks = ticks)
    }
}

/** The drawings the design has, one per family of alerts. */
enum class DrawKind { CRASH, CLOSURE, HAZARD, POLICE, JAM, CHAIN, ICE, CAMERA, TOLL, FIRE, SIGN }

/**
 * A lane drawing as a composable. With [animate] the merge arrow draws
 * itself in, the way the design does when a card opens.
 */
@Composable
fun LaneDrawing(spec: RoadSpec, kind: DrawKind, modifier: Modifier, animate: Boolean = false, key: Any? = null) {
    val p = remember(key, animate) { Animatable(if (animate) 0f else 1f) }
    LaunchedEffect(key, animate) { if (animate) { p.snapTo(0f); kotlinx.coroutines.delay(160); p.animateTo(1f, tween(860, easing = DG.easeOut)) } }
    val tm = if (spec.ticks.isNotEmpty()) rememberTextMeasurer() else null
    Canvas(modifier.graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)) {
        when (kind) {
            DrawKind.FIRE -> drawFireMap()
            DrawKind.SIGN -> drawBoard()
            else -> drawRoad(spec, p.value, tm)
        }
    }
}

/** The 76 x 64 thumbnail an alert carries. */
@Composable
fun LaneThumb(spec: RoadSpec, kind: DrawKind, modifier: Modifier = Modifier, width: Dp = 76.dp, height: Dp = 64.dp, animate: Boolean = false, key: Any? = null) {
    LaneDrawing(spec.copy(padT = 4f, padB = 6f), kind, modifier.size(width, height), animate, key)
}
