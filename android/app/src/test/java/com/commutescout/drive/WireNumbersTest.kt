package com.commutescout.drive

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/**
 * A phone set to German, French or Portuguese writes "37,3382"; the
 * server refuses that and the map stays empty with no error. Every
 * number on the wire goes through one formatter that never does.
 */
class WireNumbersTest {
    private val before: Locale = Locale.getDefault()

    @After fun restore() { Locale.setDefault(before) }

    @Test fun decimalPointInEveryLocale() {
        for (l in listOf(Locale.GERMANY, Locale.FRANCE, Locale("pt", "BR"), Locale("ar", "EG"), Locale.US)) {
            Locale.setDefault(l)
            assertEquals("37.33820", Backend.num(37.3382))
            assertEquals("-121.8863", Backend.num(-121.8863, 4))
            assertEquals("45", Backend.num(45.4, 0))
            assertEquals("https://commutescout.com/map?focus=37.33820,-121.88630", Backend.mapUrl(37.3382, -121.8863))
        }
    }
}
