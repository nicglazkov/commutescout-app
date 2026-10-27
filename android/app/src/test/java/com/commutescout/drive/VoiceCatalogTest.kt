package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The bundled catalog is shared/voices.json, read the way the app reads it. */
class VoiceCatalogTest {
    private val catalog = VoiceCatalog.parse(File("../../shared/voices.json").readText())

    @Test fun parsesBothPacks() {
        assertEquals(1, catalog.schema)
        assertEquals("voices-v1", catalog.release)
        assertEquals(listOf("supertonic2-en", "kokoro-en-v1_0"), catalog.packs.map { it.id })
        val kokoro = catalog.pack("kokoro-en-v1_0")!!
        assertTrue(kokoro.isKokoro)
        assertEquals(24_000, kokoro.sampleRate)
        assertEquals("normalized", kokoro.textInput)
        assertEquals(listOf("lexicon-us-en.txt", "lexicon-us-en-extra.txt"), kokoro.lexicons["en-US"])
        assertEquals(8, kokoro.voices.size)
        assertEquals("Harper", kokoro.defaultVoice?.name)
        val supertonic = catalog.pack("supertonic2-en")!!
        assertEquals(5, supertonic.generation.numSteps)
        assertEquals(mapOf("lang" to "en"), supertonic.generation.extra)
    }

    @Test fun everyFileHasAHashAndTheSizesAddUp() {
        for (p in catalog.packs) {
            assertEquals(p.id, p.downloadSize, p.files.sumOf { it.size })
            for (f in p.files) {
                assertTrue(f.name, Regex("[0-9a-f]{64}").matches(f.sha256))
                // "<pack>.<file>", or "<pack>.v2.<file>" for a later build of a file that keeps its name.
                val asset = f.url.substringAfterLast("/")
                val tag = asset.removePrefix(p.id + ".v").removeSuffix("." + f.name)
                assertTrue(f.url, f.url.contains("/${catalog.release}/") &&
                    (asset == p.id + "." + f.name || (asset.startsWith(p.id + ".v") && asset.endsWith("." + f.name) && tag.isNotEmpty() && tag.all { it.isDigit() })))
            }
            assertTrue(p.files.any { it.name == "LICENSE" } && p.files.any { it.name == "NOTICE" })
            for (v in p.voices) {
                assertTrue(v.id.startsWith(p.id + "."))
                assertNotNull(v.id, v.preview?.url)
            }
        }
    }

    @Test fun eachEngineHasEveryFileItNeeds() {
        val k = catalog.pack("kokoro-en-v1_0")!!
        for (role in listOf("model", "voices", "tokens")) assertNotNull(role, k.file(role))
        for (names in k.lexicons.values) for (n in names) assertNotNull(n, k.files.firstOrNull { it.name == n })
        val s = catalog.pack("supertonic2-en")!!
        for (role in listOf("duration_predictor", "text_encoder", "vector_estimator", "vocoder", "tts_json", "unicode_indexer", "voice_style"))
            assertNotNull(role, s.file(role))
    }

    @Test fun supertonicStaysHiddenUntilCleared() {
        assertFalse(VoiceCatalogRules.SUPERTONIC_CLEARED)
        assertEquals(listOf("kokoro-en-v1_0"), catalog.listed.map { it.id })
        assertNull(catalog.voice("supertonic2-en.F3"))
        assertEquals("Harper", catalog.voice("kokoro-en-v1_0.af_heart")?.name)
    }

    @Test fun kokoroEnginesAreOnePerAccent() {
        val harper = catalog.voice("kokoro-en-v1_0.af_heart")!!
        val george = catalog.voice("kokoro-en-v1_0.bm_george")!!
        val ruby = catalog.voice("kokoro-en-v1_0.af_bella")!!
        assertEquals(harper.engineKey, ruby.engineKey)
        assertFalse(harper.engineKey == george.engineKey)
        assertEquals("UK English · Male", george.description)
    }
}
