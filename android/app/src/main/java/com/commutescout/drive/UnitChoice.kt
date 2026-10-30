package com.commutescout.drive

import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Units and region: distance, clock and temperature, each either
 * "Match my phone" or forced one way. Pure, so it is tested without a
 * phone; Prefs stores the choices and [UnitStyle] holds what they come
 * to for the formatters that cannot reach Prefs.
 */
enum class DistanceChoice(val label: String) { AUTO("Match my phone"), MILES("Miles"), KM("Kilometers") }
enum class ClockChoice(val label: String) { AUTO("Match my phone"), H12("12-hour"), H24("24-hour") }
enum class TempChoice(val label: String) { AUTO("Match my phone"), F("Fahrenheit"), C("Celsius") }

object UnitRules {
    /** Regions that drive in miles. */
    private val MILES = setOf("US", "GB", "LR", "MM", "PR", "VI", "GU", "AS", "MP")
    /** Regions that read the weather in Fahrenheit. */
    private val FAHRENHEIT = setOf("US", "LR", "MM", "BS", "BZ", "KY", "PW", "FM", "MH", "PR", "VI", "GU", "AS", "MP")

    fun regionMiles(country: String): Boolean = country.uppercase() in MILES
    fun regionFahrenheit(country: String): Boolean = country.uppercase() in FAHRENHEIT

    fun miles(choice: DistanceChoice, phoneMiles: Boolean): Boolean = when (choice) {
        DistanceChoice.AUTO -> phoneMiles; DistanceChoice.MILES -> true; DistanceChoice.KM -> false
    }
    fun h24(choice: ClockChoice, phone24: Boolean): Boolean = when (choice) {
        ClockChoice.AUTO -> phone24; ClockChoice.H12 -> false; ClockChoice.H24 -> true
    }
    fun fahrenheit(choice: TempChoice, phoneF: Boolean): Boolean = when (choice) {
        TempChoice.AUTO -> phoneF; TempChoice.F -> true; TempChoice.C -> false
    }

    /** The line under "Match my phone": what the phone's setting comes to. */
    fun autoDistance(phoneMiles: Boolean) = (if (phoneMiles) "Miles" else "Kilometers") + ", from your region"
    fun autoClock(phone24: Boolean) = (if (phone24) "24-hour" else "12-hour") + ", from your phone"
    fun autoTemp(phoneF: Boolean) = (if (phoneF) "Fahrenheit" else "Celsius") + ", from your region"

    fun clockPattern(h24: Boolean) = if (h24) "HH:mm" else "h:mm a"
    fun clock(t: LocalTime, h24: Boolean): String = t.format(DateTimeFormatter.ofPattern(clockPattern(h24), Locale.US))
    fun temperature(celsius: Double, fahrenheit: Boolean): String =
        if (fahrenheit) "${Math.round(celsius * 9 / 5 + 32)}°F" else "${Math.round(celsius).let { if (it < 0) "−${-it}" else "$it" }}°C"

    /** The short summary on the Settings home row: "Miles, 12-hour". */
    fun summary(miles: Boolean, h24: Boolean) = (if (miles) "Miles" else "Kilometers") + ", " + (if (h24) "24-hour" else "12-hour")
}

/**
 * What the unit choices come to right now, for formatting code that is
 * pure or runs without the app (EventText, the trip card). The app sets
 * these from Prefs; tests leave the defaults.
 */
object UnitStyle {
    @Volatile var h24: Boolean = false
    /** Null: follow the distance unit, as before the choice was its own. */
    @Volatile var fahrenheit: Boolean? = null

    val clockPattern: String get() = UnitRules.clockPattern(h24)
}
