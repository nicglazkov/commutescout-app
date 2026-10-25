package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Kotlin port of scripts/voices/norm.py. Each expected line is that
 * script's output for the input: the two
 * apps must say the same thing, and the reference is the one to change.
 */
class KokoroTextTest {
    private val reference = listOf(
        "Take US 101 N toward San Francisco" to "Take U S one oh one North toward San Francisco",
        "Merge onto I-80 E" to "Merge onto I eighty East",
        "Continue on CA 17 for 12 mi" to "Continue on C A seventeen for twelve miles",
        "Turn right onto Main St" to "Turn right onto Main Street",
        "In 0.5 mi, turn left onto Sepulveda Blvd" to "In zero point five miles, turn left onto Sepulveda Boulevard",
        "Exit 405 onto I 405 S" to "Exit four hundred five onto I four oh five South",
        "CHP reports a crash on SR 1 near Elm Ave" to "C H P reports a crash on State Route one near Elm Avenue",
        "Speed limit 65 mph" to "Speed limit sixty five miles per hour",
        "In 500 ft, turn right onto W 3rd St" to "In five hundred feet, turn right onto West third Street",
        "Continue for 2.25 km on Hwy 280" to "Continue for two point two five kilometers on Highway two eighty",
        "Take exit 23B toward Route 66" to "Take exit twenty three B toward Route sixty six",
        "Interstate 5 has 1500 cars" to "Interstate five has one thousand five hundred cars",
        "In 1200 ft, keep left at the fork" to "In one thousand two hundred feet, keep left at the fork",
        "Roadwork for 1234567 ft on Highway 99" to "Roadwork for one two three four five six seven feet on Highway ninety nine",
        "Turn onto Dr Martin Luther King Jr Blvd" to "Turn onto Drive Martin Luther King Jr Boulevard",
        "Drive 100 miles on US 100" to "Drive one hundred miles on U S one oh zero",
        "Head north on 1st Ave, then E 42nd St" to "Head north on first Avenue, then East forty second Street",
        "Police reported ahead, in one mile" to "Police reported ahead, in one mile",
        "Turn right onto 3rd St" to "Turn right onto third Street",
        "Take exit 5A" to "Take exit five A",
        "G5 Rd" to "G five Road",
        "112th St" to "one hundred twelfth Street",
        "Continue on 21st Ave" to "Continue on twenty first Avenue",
    )

    @Test fun matchesTheReference() {
        for ((input, expected) in reference) assertEquals(input, expected, KokoroText.normalize(input))
    }

    @Test fun routeNumbersAsDriversSayThem() {
        assertEquals("one oh one", KokoroText.routeNumber("101"))
        assertEquals("eighty", KokoroText.routeNumber("80"))
        assertEquals("four oh five", KokoroText.routeNumber("405"))
        assertEquals("two eighty", KokoroText.routeNumber("280"))
        assertEquals("two fifteen", KokoroText.routeNumber("215"))
    }

    @Test fun numberWords() {
        assertEquals("zero", KokoroText.words(0))
        assertEquals("forty", KokoroText.words(40))
        assertEquals("nine hundred ninety nine", KokoroText.words(999))
        assertEquals("twenty one thousand", KokoroText.words(21_000))
        assertEquals("one two zero zero zero zero zero", KokoroText.words(1_200_000))
    }

    @Test fun digitsLongerThanAnIntAreReadOneByOne() {
        assertEquals("one two three four five six seven eight nine zero one two", KokoroText.normalize("123456789012"))
    }

    @Test fun unknownWordsAreFound() {
        val lex = LexiconIndex.of(sequenceOf("in", "half", "a", "mile", "turn", "right", "onto", "main", "street", "driver's"))
        assertTrue("main" in lex)
        assertFalse("sepulveda" in lex)
        assertEquals(emptyList<String>(), KokoroText.unknownWords("In half a mile, turn right onto Main Street.") { it in lex })
        assertEquals(listOf("sepulveda"), KokoroText.unknownWords("Turn right onto Sepulveda Street") { it in lex })
        assertEquals(emptyList<String>(), KokoroText.unknownWords("'Driver's' street") { it in lex })
    }

    @Test fun lexiconLinesAreWordThenPhonemes() {
        val f = java.io.File.createTempFile("lex", ".txt")
        try {
            f.writeText("kokoro k ˈ O k ə ɹ O\nAaron ˈ ɛ ɹ ə n\na.m. ˌ A ˈ ɛ m\n\n")
            val lex = LexiconIndex.load(listOf(f))
            assertEquals(3, lex.size)
            assertTrue("kokoro" in lex && "aaron" in lex && "a.m." in lex)
        } finally { f.delete() }
    }
}
