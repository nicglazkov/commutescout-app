package com.commutescout.drive

/**
 * The small notices that can appear over the map on a trip, and the
 * rule for the one about speed. Each has its own switch on the
 * Notices page; only the speed one starts switched off.
 */
object TripNotices {
    /** The amounts over the limit offered as one-tap choices, in the display unit. */
    val steps = listOf(0, 5, 10, 15, 20)
    const val defaultOver = 5
    const val maxOver = 60

    /** A typed amount over the limit, or null when it is not a whole number from 0 to [maxOver]. */
    fun typedOver(text: String): Int? = text.trim().toIntOrNull()?.takeIf { it in 0..maxOver }

    /** True when the speed notice should show: switched on, moving, a known limit, and past it by more than [overBy]. */
    fun speeding(on: Boolean, speed: Int, limit: Int?, overBy: Int, moving: Boolean): Boolean =
        on && moving && limit != null && limit > 0 && speed > limit + overBy

    /** "More than 5 mph over", or "Any speed over the limit" for zero. */
    fun overLabel(overBy: Int, unit: String): String = if (overBy <= 0) "Any speed over the limit" else "More than $overBy $unit over the limit"
}
