package com.commutescout.drive

import java.io.File

/**
 * The text rules Kokoro needs before it speaks. Kokoro reads words
 * through its lexicons only: it has no rules for numbers or
 * abbreviations, and it skips a word it does not know without a sound.
 *
 * A port of scripts/voices/norm.py, the reference for both apps.
 * KokoroTextTest checks it against that script's output. Supertonic
 * reads raw text and does not use this.
 */
object KokoroText {
    private val ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split(" ")
    private val TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split(" ")

    fun words(n: Int): String = when {
        n < 20 -> ONES[n]
        n < 100 -> TENS[n / 10] + if (n % 10 == 0) "" else " " + ONES[n % 10]
        n < 1000 -> ONES[n / 100] + " hundred" + if (n % 100 == 0) "" else " " + words(n % 100)
        n < 1_000_000 -> words(n / 1000) + " thousand" + if (n % 1000 == 0) "" else " " + words(n % 1000)
        else -> n.toString().map { ONES[it - '0'] }.joinToString(" ")
    }

    /** [words] for a run of digits of any length: a million and up is read digit by digit. */
    private fun wordsOf(digits: String): String {
        val trimmed = digits.trimStart('0').ifEmpty { "0" }
        return if (trimmed.length > 6) trimmed.map { ONES[it - '0'] }.joinToString(" ") else words(trimmed.toInt())
    }

    /** Road numbers the way drivers say them: 101 "one oh one", 80 "eighty", 405 "four oh five". */
    fun routeNumber(n: String): String {
        val i = n.toInt()
        if (i < 100) return words(i)
        if (n.length == 3 && n[1] == '0') return ONES[n[0] - '0'] + " oh " + ONES[n[2] - '0']
        if (n.length == 3) return ONES[n[0] - '0'] + " " + words(n.substring(1).toInt())
        return words(i)
    }

    private val ROUTE = Regex("""\b(I|US|CA|SR|Hwy|Highway|Route|Interstate)[- ]?(\d{1,3})\b""")
    private val PREFIX = mapOf("I" to "I", "US" to "U S", "CA" to "C A", "SR" to "State Route", "Hwy" to "Highway",
        "Highway" to "Highway", "Route" to "Route", "Interstate" to "Interstate")
    // In the reference's order: each rule sees the text the ones before it left.
    private val ABBR = listOf(
        "St" to "Street", "Ave" to "Avenue", "Blvd" to "Boulevard", "Rd" to "Road", "Dr" to "Drive",
        "N" to "North", "S" to "South", "E" to "East", "W" to "West", "mph" to "miles per hour",
        "CHP" to "C H P", "mi" to "miles", "km" to "kilometers", "ft" to "feet",
    ).map { (k, v) -> Regex("""\b$k\b""") to v }
    private val ORDINAL = Regex("""\b(\d+)(st|nd|rd|th)\b""")
    private val DECIMAL = Regex("""(\d+)\.(\d+)""")
    private val CODE = Regex("""\b([A-Za-z]+)(\d+)\b""")
    private val EXIT = Regex("""\b(\d+)([A-Za-z])\b""")
    private val NUMBER = Regex("""\d+""")
    private val IRREGULAR = mapOf("one" to "first", "two" to "second", "three" to "third", "five" to "fifth",
        "eight" to "eighth", "nine" to "ninth", "twelve" to "twelfth")

    /** 3rd "third", 21st "twenty first", 112th "one hundred twelfth": only the last word changes. */
    fun ordinal(digits: String): String {
        val parts = wordsOf(digits).split(" ")
        val last = parts.last()
        val said = IRREGULAR[last] ?: if (last.endsWith("y")) last.dropLast(1) + "ieth" else last + "th"
        return (parts.dropLast(1) + said).joinToString(" ")
    }

    /** A short all-caps run is a code, said letter by letter: G5 "G five". */
    private fun letters(s: String): String =
        if (s.length <= 3 && s.all { it.isUpperCase() }) s.toList().joinToString(" ") else s

    fun normalize(text: String): String {
        var t = text
        for ((k, v) in ABBR) t = k.replace(t, v)
        t = ROUTE.replace(t) { m -> PREFIX.getValue(m.groupValues[1]) + " " + routeNumber(m.groupValues[2]) }
        t = ORDINAL.replace(t) { m -> ordinal(m.groupValues[1]) }
        t = DECIMAL.replace(t) { m -> wordsOf(m.groupValues[1]) + " point " + m.groupValues[2].map { ONES[it - '0'] }.joinToString(" ") }
        t = CODE.replace(t) { m -> letters(m.groupValues[1]) + " " + wordsOf(m.groupValues[2]) }
        t = EXIT.replace(t) { m -> wordsOf(m.groupValues[1]) + " " + m.groupValues[2] }
        t = NUMBER.replace(t) { m -> wordsOf(m.value) }
        return t
    }

    private val SPLIT = Regex("""[^a-z']+""")

    /** The words of [text] the way the lexicon lists them: lower case, apostrophes kept. */
    fun lexiconWords(text: String): List<String> =
        text.lowercase().split(SPLIT).map { it.trim('\'') }.filter { it.isNotEmpty() }

    /** Words of normalized [text] that [known] does not have; Kokoro would skip each of them silently. */
    fun unknownWords(text: String, known: (String) -> Boolean): List<String> = lexiconWords(text).filter { !known(it) }.distinct()
}

/**
 * The words a Kokoro lexicon knows, as a sorted array of 64-bit hashes:
 * about 1.5 MB for the 200,000 words of both files, where a set of
 * strings would take ten times that.
 */
class LexiconIndex private constructor(private val hashes: LongArray) {
    val size: Int get() = hashes.size
    operator fun contains(word: String): Boolean = java.util.Arrays.binarySearch(hashes, hash(word)) >= 0

    companion object {
        fun hash(s: String): Long {
            var h = -0x340d631b7bdddcdbL // FNV-1a offset basis
            for (c in s) {
                h = h xor c.code.toLong()
                h *= 0x100000001b3L
            }
            return h
        }

        fun of(words: Sequence<String>): LexiconIndex {
            var arr = LongArray(1 shl 16)
            var n = 0
            for (w in words) {
                if (n == arr.size) arr = arr.copyOf(arr.size * 2)
                arr[n++] = hash(w)
            }
            arr = arr.copyOf(n)
            arr.sort()
            return LexiconIndex(arr)
        }

        /** Each line of a lexicon is the word, a space, then its phonemes. */
        fun load(files: List<File>): LexiconIndex = of(sequence {
            for (f in files) f.bufferedReader().useLines { lines ->
                for (line in lines) {
                    val end = line.indexOfFirst { it == ' ' || it == '\t' }
                    val w = if (end < 0) line else line.substring(0, end)
                    if (w.isNotEmpty()) yield(w.lowercase())
                }
            }
        })
    }
}
