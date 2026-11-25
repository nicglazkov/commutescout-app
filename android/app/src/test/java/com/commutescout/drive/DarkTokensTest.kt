package com.commutescout.drive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.Tone
import com.commutescout.drive.design.tint
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DarkTokensTest {
    @After fun reset() { DG.dark = false }

    @Test fun dayKeepsTheDesignColors() {
        DG.dark = false
        assertEquals(Color(0xFF0E1726), DG.ink)
        assertEquals(Color.White, DG.surface)
        assertEquals(Color.White.copy(alpha = .7f), DG.glass(.7f))
    }

    @Test fun nightFlipsInkAndSurfaces() {
        DG.dark = true
        assertTrue(DG.ink.luminance() > .8f)
        for (c in listOf(DG.surface, DG.bg, DG.page, DG.glass(1f), DG.raised, DG.solid)) assertTrue(c.luminance() < .06f)
    }

    @Test fun wordsOnATintStayReadableAtNight() {
        DG.dark = true
        for (t in Tone.entries) {
            val ground = t.color.tint(.12f)
            val contrast = (t.ink.luminance() + .05f) / (ground.luminance() + .05f)
            assertTrue("$t $contrast", contrast >= 4.5f)
        }
    }

    @Test fun whiteWordsReadOnASolidButtonBothWays() {
        for (dark in listOf(false, true)) {
            DG.dark = dark
            assertTrue((1.05f) / (DG.solid.luminance() + .05f) >= 7f)
        }
    }
}
