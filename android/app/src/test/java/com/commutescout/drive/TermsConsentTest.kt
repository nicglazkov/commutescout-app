package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TermsConsentTest {
    @Test fun versionMatchesTheServer() {
        // The server's TERMS_VERSION (ca_roads_demo.watch); bump both together.
        assertEquals("2026-11-19", TermsConsent.VERSION)
        assertEquals("""{"version":"2026-11-19"}""", TermsConsent.body())
    }

    @Test fun signInWaitsForTheTickOnAPhoneThatHasNotAgreed() {
        assertFalse(TermsConsent.canSignIn(stored = null, ticked = false))
        assertTrue(TermsConsent.canSignIn(stored = null, ticked = true))
        // An older version asks again.
        assertFalse(TermsConsent.canSignIn(stored = "2025-01-01", ticked = false))
        // Agreed here to this version: a passive line, no box.
        assertTrue(TermsConsent.agreed(TermsConsent.VERSION))
        assertTrue(TermsConsent.canSignIn(stored = TermsConsent.VERSION, ticked = false))
    }

    @Test fun linksPointAtTheSite() {
        assertEquals("https://commutescout.com/terms", TermsConsent.TERMS_URL)
        assertEquals("https://commutescout.com/privacy", TermsConsent.PRIVACY_URL)
    }

    @Test fun welcomeSaysLocationIsNeverSoldNotNeverShared() {
        val loc = WelcomeSteps.steps.first { it.ask == WelcomeSteps.Ask.LOCATION }.askBody!!
        assertTrue(loc.contains("never sold"))
        assertFalse(loc.contains("never shared"))
    }
}
