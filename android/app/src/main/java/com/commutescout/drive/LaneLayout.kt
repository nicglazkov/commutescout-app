package com.commutescout.drive

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * How the lanes sit at an event, as the server sends it in a marker's
 * `lane_layout`. Lanes run left to right in the direction of travel,
 * `n = 1` the leftmost. Every field is optional on the wire; anything
 * that does not make sense is dropped here so the drawing never has to
 * guess.
 */
data class LaneLayout(
    val total: Int,
    val lanes: List<Lane>,
    /** True for an open shoulder, false for a closed one, null when there is none. */
    val shoulderLeft: Boolean? = null,
    val shoulderRight: Boolean? = null,
    /** The lane to move to, 1-based, or null when there is no advice. */
    val target: Int? = null,
    /** feed, count_only or lookup: how much of this is known. */
    val basis: String? = null,
) {
    data class Lane(val n: Int, val type: String = "general", val closed: Boolean = false)

    val closedLanes: List<Int> get() = lanes.filter { it.closed }.map { it.n }
    val anyLaneClosed: Boolean get() = lanes.any { it.closed }
    val shoulderClosed: Boolean get() = shoulderLeft == false || shoulderRight == false

    /**
     * Where the merge arrow goes: from the closed lane nearest the
     * target to the target. Null for no arrow: no target, or nothing
     * but a shoulder closed.
     */
    val merge: Pair<Int, Int>? get() {
        val to = target ?: return null
        val from = closedLanes.minByOrNull { kotlin.math.abs(it - to) } ?: return null
        return if (from == to) null else from to to
    }

    /** "Move one lane left." and the like, or null with no merge. */
    val advice: String? get() {
        val (from, to) = merge ?: return null
        val steps = kotlin.math.abs(to - from)
        val side = if (to < from) "left" else "right"
        val count = when (steps) { 1 -> "one lane"; 2 -> "two lanes"; 3 -> "three lanes"; else -> "$steps lanes" }
        return "Move $count $side."
    }


    /**
     * The lanes in a few words, as the alert's second line says them:
     * "Right lane blocked", "2 right lanes closed", "Right shoulder
     * closed". Null when nothing is closed.
     */
    val summary: String? get() {
        val c = closedLanes
        if (c.isEmpty()) return when {
            shoulderRight == false && shoulderLeft == false -> "Both shoulders closed"
            shoulderRight == false -> "Right shoulder closed"
            shoulderLeft == false -> "Left shoulder closed"
            else -> null
        }
        if (c.size == total) return "All lanes closed"
        val fromRight = c == ((total - c.size + 1)..total).toList()
        val fromLeft = c == (1..c.size).toList()
        return when {
            c.size == 1 && c[0] == total -> "Right lane blocked"
            c.size == 1 && c[0] == 1 -> "Left lane blocked"
            c.size == 1 -> "Lane ${c[0]} of $total blocked"
            fromRight -> "${c.size} right lanes closed"
            fromLeft -> "${c.size} left lanes closed"
            else -> "${c.size} of $total lanes closed"
        }
    }

    companion object {
        val TYPES = setOf("general", "hov", "express", "exit", "aux")

        /** The layout from the wire, or null when there is none worth drawing. */
        fun from(e: JsonElement?): LaneLayout? = runCatching { parse(e) }.getOrNull()

        private fun num(e: JsonElement?): Int? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull }?.doubleOrNull?.toInt()
        private fun str(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it.isString }?.content

        private fun parse(e: JsonElement?): LaneLayout? {
            val o = e as? JsonObject ?: return null
            val raw = (o["lanes"] as? JsonArray).orEmpty().mapNotNull { l ->
                val lo = l as? JsonObject ?: return@mapNotNull null
                val n = num(lo["n"]) ?: return@mapNotNull null
                Lane(n, str(lo["type"])?.takeIf { it in TYPES } ?: "general", str(lo["state"]) == "closed")
            }
            val total = (num(o["total"]) ?: raw.maxOfOrNull { it.n } ?: return null).coerceIn(0, 12)
            if (total < 1) return null
            // Every lane from 1 to total, once: missing ones are open general lanes.
            val byN = raw.filter { it.n in 1..total }.associateBy { it.n }
            val lanes = (1..total).map { byN[it] ?: Lane(it) }
            val sh = o["shoulder"] as? JsonObject
            fun side(k: String): Boolean? = when (str(sh?.get(k))) { "open" -> true; "closed" -> false; else -> null }
            return LaneLayout(
                total = total, lanes = lanes,
                shoulderLeft = side("left"), shoulderRight = side("right"),
                target = num(o["target"])?.takeIf { it in 1..total },
                basis = str(o["basis"]),
            )
        }
    }
}
