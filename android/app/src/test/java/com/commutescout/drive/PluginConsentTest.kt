package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Unreviewed plugins alert only after the notice; each plugin has its own voice switch. */
class PluginConsentTest {
    @Test fun theNoticeIsTheApprovedWording() {
        assertEquals("This plugin hasn't been reviewed by CommuteScout. Its alerts come from its operator, not from official sources.",
            PluginConsent.NOTICE)
    }

    @Test fun onlyUnreviewedPluginsWait() {
        assertTrue(PluginConsent.needsAck("unreviewed"))
        assertTrue("no tier counts as unreviewed", PluginConsent.needsAck(null))
        assertFalse(PluginConsent.needsAck("approved"))
        assertFalse(PluginConsent.needsAck("private"))
        assertFalse(PluginConsent.mayAlert("unreviewed", acked = false))
        assertTrue(PluginConsent.mayAlert("unreviewed", acked = true))
        assertTrue(PluginConsent.mayAlert("approved", acked = false))
        assertTrue(PluginConsent.asksFirst("unreviewed", acked = false))
        assertFalse(PluginConsent.asksFirst("unreviewed", acked = true))
        assertFalse(PluginConsent.asksFirst("approved", acked = false))
    }

    @Test fun eachPluginHasItsOwnVoiceSwitch() {
        fun speaks(id: String, tier: String, on: Set<String> = emptySet(), off: Set<String> = emptySet(), legacy: Boolean = false) =
            PluginConsent.speaks(id, tier, on, off, legacy)
        assertFalse("voice is off until turned on", speaks("a", "approved"))
        assertFalse(speaks("u", "unreviewed"))
        assertTrue(speaks("u", "unreviewed", on = setOf("u")))
        assertFalse(speaks("a", "approved", on = setOf("u")))
        // The old all-plugins switch carries over for reviewed and private plugins only.
        assertTrue(speaks("a", "approved", legacy = true))
        assertTrue(speaks("p", "private", legacy = true))
        assertFalse(speaks("u", "unreviewed", legacy = true))
        assertFalse(speaks("a", "approved", off = setOf("a"), legacy = true))
    }
}
