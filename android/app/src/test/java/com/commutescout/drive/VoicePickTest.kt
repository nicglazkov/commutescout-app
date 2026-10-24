package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

/**
 * Which voice speaks: the order on the Voice page, the voice used when
 * none is chosen, what happens offline or when a voice is removed, and
 * the names a person reads.
 */
class VoicePickTest {
    private val us = Locale("en", "US")

    private fun v(name: String, quality: Int = 300, network: Boolean = name.endsWith("-network"), installed: Boolean = true): VoiceInfo {
        val parts = name.split("-")
        return VoiceInfo(name, parts[0], parts[1].uppercase(), quality, network = network, installed = installed)
    }

    private val google = listOf(
        v("en-gb-x-gba-local", 400),
        v("en-us-x-iob-network", 400),
        v("en-us-x-iob-local", 400),
        v("en-us-x-sfg-local", 300),
        v("en-us-x-tpf-network", 500),
        v("en-us-x-iol-local", 400, installed = false),
        v("en-au-x-aua-local", 400),
        v("fr-fr-x-frc-local", 400),
    )

    @Test fun regionFirstThenQualityThenOnDevice() {
        assertEquals(
            listOf("en-us-x-tpf-network", "en-us-x-iob-local", "en-us-x-iob-network", "en-us-x-sfg-local", "en-us-x-iol-local"),
            VoicePick.forLocale(google, us).map { it.name })
    }

    @Test fun otherAccentsComeBeforeOtherLanguages() {
        assertEquals(listOf("en-au-x-aua-local", "en-gb-x-gba-local", "fr-fr-x-frc-local"), VoicePick.others(google, us).map { it.name })
    }

    @Test fun otherLanguagesStillToDownloadAreLeftToSystemSettings() {
        val voices = google + v("en-in-x-ena-local", installed = false) + v("de-de-x-deb-local", installed = false)
        assertEquals(listOf("en-au-x-aua-local", "en-gb-x-gba-local", "en-in-x-ena-local", "fr-fr-x-frc-local"),
            VoicePick.others(voices, us).map { it.name })
    }

    @Test fun noVoiceForTheRegionListsTheWholeLanguage() {
        assertEquals(setOf("en-gb-x-gba-local", "en-au-x-aua-local", "en-us-x-iob-local", "en-us-x-iob-network",
                           "en-us-x-sfg-local", "en-us-x-tpf-network", "en-us-x-iol-local"),
            VoicePick.forLocale(google, Locale("en", "NZ")).map { it.name }.toSet())
    }

    @Test fun defaultIsTheBestVoiceOnThePhoneForTheRegion() {
        // The very high quality voice streams; the best one on the phone wins.
        assertEquals("en-us-x-iob-local", VoicePick.smartDefault(google, us, online = true)?.name)
        assertEquals("en-gb-x-gba-local", VoicePick.smartDefault(google, Locale("en", "GB"), online = true)?.name)
    }

    @Test fun defaultSkipsVoicesNotDownloaded() {
        val voices = listOf(v("en-us-x-iol-local", 500, installed = false), v("en-us-x-sfg-local", 300))
        assertEquals("en-us-x-sfg-local", VoicePick.smartDefault(voices, us, online = true)?.name)
    }

    @Test fun defaultUsesANetworkVoiceOnlyWhenNothingElseSpeaksTheLanguage() {
        val voices = listOf(v("en-us-x-tpf-network", 500), v("fr-fr-x-frc-local", 400))
        assertEquals("en-us-x-tpf-network", VoicePick.smartDefault(voices, us, online = true)?.name)
        assertNull(VoicePick.smartDefault(voices, us, online = false))
    }

    @Test fun savedVoiceIsKept() {
        assertEquals("en-us-x-sfg-local", VoicePick.resolve("en-us-x-sfg-local", google, us, online = false)?.name)
        assertEquals("fr-fr-x-frc-local", VoicePick.resolve("fr-fr-x-frc-local", google, us, online = false)?.name)
        assertEquals("en-us-x-tpf-network", VoicePick.resolve("en-us-x-tpf-network", google, us, online = true)?.name)
    }

    @Test fun offlineNetworkVoiceHandsOverToItsTwinOnThePhone() {
        assertEquals("en-us-x-iob-local", VoicePick.resolve("en-us-x-iob-network", google, us, online = false)?.name)
    }

    @Test fun offlineNetworkVoiceWithNoTwinFallsBackToTheDefault() {
        assertEquals("en-us-x-iob-local", VoicePick.resolve("en-us-x-tpf-network", google, us, online = false)?.name)
    }

    @Test fun removedOrUndownloadedVoiceFallsBackToTheDefault() {
        assertEquals("en-us-x-iob-local", VoicePick.resolve("en-us-x-gone-local", google, us, online = true)?.name)
        assertEquals("en-us-x-iob-local", VoicePick.resolve("en-us-x-iol-local", google, us, online = true)?.name)
        assertEquals("en-us-x-iob-local", VoicePick.resolve("", google, us, online = true)?.name)
    }

    @Test fun nothingUsableLeavesTheEngineDefault() {
        assertNull(VoicePick.resolve("", emptyList(), us, online = true))
        assertNull(VoicePick.resolve("", listOf(v("fr-fr-x-frc-local")), us, online = true))
    }

    @Test fun friendlyNames() {
        val iob = google.first { it.name == "en-us-x-iob-local" }
        // US voices by id: iob, iol, sfg, tpf.
        assertEquals("English (US) · Voice 1 · High quality · On device", VoiceLabels.full(iob, google))
        assertEquals("English (US) · Voice 1", VoiceLabels.title(google.first { it.name == "en-us-x-iob-network" }, google))
        assertEquals("Very high quality · Needs a connection", VoiceLabels.detail(google.first { it.name == "en-us-x-tpf-network" }))
        assertEquals("Not downloaded", VoiceLabels.detail(google.first { it.name == "en-us-x-iol-local" }))
        assertEquals("English (US) · Voice 4", VoiceLabels.title(google.first { it.name == "en-us-x-tpf-network" }, google))
        assertEquals("English (UK) · Voice 1", VoiceLabels.title(google.first { it.name == "en-gb-x-gba-local" }, google))
        assertEquals("English (Australia)", VoiceLabels.language("en", "AU"))
        assertEquals("French", VoiceLabels.language("fr", ""))
    }

    @Test fun nonGoogleNamesStillGetAnId() {
        assertEquals("language", VoiceLabels.id(VoiceInfo("en-US-language", "en", "US", 300)))
        assertEquals("smtl01", VoiceLabels.id(VoiceInfo("en-US-SMTl01", "en", "US", 400)))
    }

    @Test fun googlesDefaultAliasIsNotListedTwice() {
        val alias = VoiceInfo("en-US-language", "en", "US", 400)
        val voices = listOf(alias, v("en-us-x-iob-local", 400), v("en-us-x-sfg-local", 400))
        assertEquals(listOf("en-us-x-iob-local", "en-us-x-sfg-local"), VoicePick.forLocale(voices, us).map { it.name })
        // Among equals the engine's own choice stays, so nobody's voice changes unasked.
        assertEquals("en-US-language", VoicePick.smartDefault(voices, us, online = true)?.name)
        assertEquals("English (US) · Default voice", VoiceLabels.title(alias, voices))
        assertEquals("English (US) · Voice 2", VoiceLabels.title(voices[2], voices))
        // A better voice on the phone wins over the alias.
        assertEquals("en-us-x-tpf-local", VoicePick.smartDefault(voices + v("en-us-x-tpf-local", 500), us, online = true)?.name)
        // Alone, it is listed.
        assertEquals(listOf("en-US-language"), VoicePick.forLocale(listOf(alias), us).map { it.name })
    }

    @Test fun rateAndPitchLabels() {
        assertEquals("Normal", VoiceLabels.rate(1f))
        assertEquals("1.2x", VoiceLabels.rate(1.2f))
        assertEquals("Lower", VoiceLabels.pitch(0.9f))
        assertEquals("Normal", VoiceLabels.pitch(1f))
    }

    @Test fun previewSaysATurnAndAnAlert() {
        assertEquals("In half a mile, turn right onto Main Street. Police reported ahead.", VoiceLabels.preview("half a mile"))
    }
}
