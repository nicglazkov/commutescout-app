package com.commutescout.drive

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The account token goes only to CommuteScout's own plugin hosts. */
class FirstPartyTest {
    @Test fun ownHostsAreFirstParty() {
        assertTrue(isFirstParty("https://wz-flare-15002631928.us-west1.run.app"))
        assertTrue(isFirstParty("https://commutescout.com"))
        assertTrue(isFirstParty("https://plugins.commutescout.com/x"))
    }

    @Test fun lookalikesAndOtherHostsAreNot() {
        assertFalse(isFirstParty("https://example.com"))
        assertFalse(isFirstParty("https://evilcommutescout.com"))
        assertFalse(isFirstParty("https://commutescout.com.evil.example"))
        assertFalse(isFirstParty("https://x-15002631928.us-west1.run.app.evil.example"))
        assertFalse(isFirstParty("https://x-99999999999.us-west1.run.app"))
        assertFalse(isFirstParty("http://commutescout.com"))
        assertFalse(isFirstParty("https://commutescout.com:8443"))
        assertFalse(isFirstParty("https://a@evil.example"))
        assertFalse(isFirstParty("not a url"))
    }
}
