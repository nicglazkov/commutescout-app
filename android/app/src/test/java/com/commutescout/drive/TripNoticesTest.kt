package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TripNoticesTest {
    @Test fun theSpeedNoticeIsSilentUntilSwitchedOn() {
        assertFalse(TripNotices.speeding(on = false, speed = 90, limit = 65, overBy = 5, moving = true))
        assertTrue(TripNotices.speeding(on = true, speed = 90, limit = 65, overBy = 5, moving = true))
    }

    @Test fun itWaitsForMoreThanTheChosenAmount() {
        assertFalse(TripNotices.speeding(true, 70, 65, 5, true))
        assertTrue(TripNotices.speeding(true, 71, 65, 5, true))
        assertFalse(TripNotices.speeding(true, 80, 65, 15, true))
        assertTrue(TripNotices.speeding(true, 66, 65, 0, true))
        assertFalse(TripNotices.speeding(true, 65, 65, 0, true))
    }

    @Test fun noLimitOrStandingStillShowsNothing() {
        assertFalse(TripNotices.speeding(true, 90, null, 5, true))
        assertFalse(TripNotices.speeding(true, 90, 0, 5, true))
        assertFalse(TripNotices.speeding(true, 90, 65, 5, moving = false))
    }

    @Test fun aTypedAmountMustBeAWholeNumberInRange() {
        assertEquals(12, TripNotices.typedOver(" 12 "))
        assertEquals(0, TripNotices.typedOver("0"))
        assertNull(TripNotices.typedOver(""))
        assertNull(TripNotices.typedOver("7.5"))
        assertNull(TripNotices.typedOver("-3"))
        assertNull(TripNotices.typedOver("200"))
    }

    @Test fun theLabelSaysTheAmountInTheDriversUnit() {
        assertEquals("More than 10 mph over the limit", TripNotices.overLabel(10, "mph"))
        assertEquals("Any speed over the limit", TripNotices.overLabel(0, "km/h"))
    }
}
