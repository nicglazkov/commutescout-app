package com.commutescout.drive

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Automatic's choice, the download checks, and when the system voice takes over. */
class NeuralVoiceTest {
    private val catalog = VoiceCatalog.parse(File("../../shared/voices.json").readText())
    private val kokoro = "kokoro-en-v1_0"

    // Automatic

    @Test fun automaticUsesTheSystemPickWithNoPack() {
        assertNull(NeuralPick.choose("", catalog, emptySet()))
    }

    @Test fun automaticUsesHarperOnceKokoroIsInstalled() {
        assertEquals("kokoro-en-v1_0.af_heart", NeuralPick.choose("", catalog, setOf(kokoro))?.id)
    }

    @Test fun automaticNeverPicksAHiddenPack() {
        // Supertonic is the catalog default, but it is not cleared to ship.
        assertNull(NeuralPick.choose("", catalog, setOf("supertonic2-en")))
        assertEquals("Harper", NeuralPick.choose("", catalog, setOf("supertonic2-en", kokoro))?.name)
        assertNull(NeuralPick.choose("supertonic2-en.F3", catalog, setOf("supertonic2-en")))
    }

    @Test fun aChosenVoiceSpeaksWhileItsPackIsThere() {
        assertEquals("George", NeuralPick.choose("kokoro-en-v1_0.bm_george", catalog, setOf(kokoro))?.name)
        // Deleted: the system voice speaks.
        assertNull(NeuralPick.choose("kokoro-en-v1_0.bm_george", catalog, emptySet()))
    }

    @Test fun aChosenSystemVoiceStaysASystemVoice() {
        assertNull(NeuralPick.choose("en-us-x-iob-local", catalog, setOf(kokoro)))
        assertFalse(NeuralPick.isNeural("en-us-x-iob-local", catalog))
        assertTrue(NeuralPick.isNeural("kokoro-en-v1_0.bm_george", catalog))
    }

    // Download checks

    private fun tmpDir(): File = Files.createTempDirectory("pack").toFile()

    private fun sha(bytes: ByteArray) = java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun packOf(vararg files: Pair<String, ByteArray>): VoicePackInfo = VoicePackInfo(
        id = "test", title = "Test voices", engine = "kokoro", sampleRate = 24_000,
        license = VoicePackInfo.License("Apache-2.0", "Apache License 2.0"), attribution = "", voices = emptyList(),
        files = files.map { (n, b) -> PackFile(n, "x", "https://example.invalid/$n", sha(b), b.size.toLong()) },
        downloadSize = files.sumOf { it.second.size.toLong() },
    )

    @Test fun aFileIsKeptOnlyWhenSizeAndHashMatch() {
        val dir = tmpDir()
        try {
            val good = "hello voices".toByteArray()
            val pack = packOf("model.onnx" to good)
            val f = File(dir, "model.onnx")
            f.writeBytes(good)
            assertTrue(PackFiles.verify(f, pack.files[0]))
            f.writeBytes("hello voiceZ".toByteArray()) // same size, other bytes
            assertFalse(PackFiles.verify(f, pack.files[0]))
            f.writeBytes("hello".toByteArray())
            assertFalse(PackFiles.verify(f, pack.files[0]))
            assertFalse(PackFiles.verify(File(dir, "missing"), pack.files[0]))
        } finally { dir.deleteRecursively() }
    }

    @Test fun aPartialFileResumesWhereItStopped() {
        val dir = tmpDir()
        try {
            val pack = packOf("a" to ByteArray(100), "b" to ByteArray(50))
            File(dir, "a").writeBytes(ByteArray(100))
            val part = File(dir, "b.part").apply { writeBytes(ByteArray(20)) }
            assertEquals(20, PackFiles.resumeFrom(part, pack.files[1]))
            assertEquals(120, PackFiles.bytesOnDisk(dir, pack))
            assertEquals(33, PackFiles.spaceNeeded(dir, pack)) // (150 - 120) * 1.1
            // Longer than the file can be: started again.
            part.writeBytes(ByteArray(60))
            assertEquals(0, PackFiles.resumeFrom(part, pack.files[1]))
            assertFalse(part.exists())
        } finally { dir.deleteRecursively() }
    }

    @Test fun installedNeedsTheMarkerAndEveryFile() {
        val dir = tmpDir()
        try {
            val pack = packOf("a" to ByteArray(10), "b" to ByteArray(5))
            File(dir, "a").writeBytes(ByteArray(10))
            File(dir, "b").writeBytes(ByteArray(5))
            assertFalse(PackFiles.installed(dir, pack))
            File(dir, PackFiles.MARKER).writeText("ok")
            assertTrue(PackFiles.installed(dir, pack))
            File(dir, "b").writeBytes(ByteArray(4)) // corrupt or cut short
            assertFalse(PackFiles.installed(dir, pack))
        } finally { dir.deleteRecursively() }
    }

    // Fallback

    @Test fun kokoroWaitsBrieflyAndOnlyForAudioRenderedAhead() {
        val k = catalog.pack(kokoro)!!
        assertEquals(300, NeuralRules.waitMs(k, preview = false))
        assertFalse(NeuralRules.renderOnDemand(k, preview = false))
        // The Settings sample is not time-critical.
        assertTrue(NeuralRules.renderOnDemand(k, preview = true))
        assertTrue(NeuralRules.waitMs(k, preview = true) > 5_000)
        val s = catalog.pack("supertonic2-en")!!
        assertEquals(1_000, NeuralRules.waitMs(s, preview = false))
        assertTrue(NeuralRules.renderOnDemand(s, preview = false))
    }

    @Test fun brokenAudioIsNotPlayed() {
        assertFalse(NeuralRules.usable(null))
        assertFalse(NeuralRules.usable(FloatArray(0)))
        assertFalse(NeuralRules.usable(floatArrayOf(0.1f, Float.NaN, 0.2f)))
        assertFalse(NeuralRules.usable(floatArrayOf(Float.POSITIVE_INFINITY)))
        assertTrue(NeuralRules.usable(floatArrayOf(0.1f, -0.2f)))
    }

    @Test fun samplesBecomeClippedPcm() {
        assertArrayEquals(shortArrayOf(0, 32767, -32767, 32767, -32767), NeuralRules.pcm16(floatArrayOf(0f, 1f, -1f, 2f, -3f)))
    }

    @Test fun onlyKokoroTextIsNormalized() {
        assertEquals("Take U S one oh one", NeuralRules.engineText(catalog.pack(kokoro)!!, "Take US 101"))
        assertEquals("Take US 101", NeuralRules.engineText(catalog.pack("supertonic2-en")!!, "Take US 101"))
    }

    // Rendering ahead

    @Test fun routeInstructionsInTheOrderTheyAreSpoken() {
        val steps = listOf(
            1000.0 to listOf("Head north" to 1000.0, "In 500 feet, turn right" to 150.0),
            2000.0 to listOf("In 1 mile, turn left" to 1600.0, "Turn left" to 30.0),
            0.0 to listOf("You have arrived" to 0.0),
        )
        assertEquals(listOf("Head north" to 0.0, "In 500 feet, turn right" to 850.0, "In 1 mile, turn left" to 1400.0,
            "Turn left" to 2970.0, "You have arrived" to 3000.0), NeuralRules.routeSentences(steps))
    }

    @Test fun alertSentencesAtTheirAnnounceDistances() {
        val spoken: (Double) -> String = { m -> if (m < 1300) "half a mile" else "one mile" }
        val rule = Prefs.AlertRule(true, true, 1320.0, 400.0)
        val got = AlertsEngine.likelySentences("Crash", rule, spoken)
        // The gap lands just inside 1320 m, where the spoken distance changes: both are rendered.
        assertEquals(listOf("Crash, in one mile" to 1320.0, "Crash, in half a mile" to 1320.0), got)
        // Close in, no distance is said.
        assertEquals(listOf("Police" to 150.0), AlertsEngine.likelySentences("Police", Prefs.AlertRule(true, true, 150.0, 0.0), spoken))
        assertEquals("Crash, in one mile", AlertsEngine.sentence("Crash", 1320.0, spoken))
    }
}
