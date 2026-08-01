package com.trackit

import org.junit.Assert.assertEquals
import org.junit.Test

class TrackitNotificationListenerTest {
    @Test fun stableIdsAreDeterministic() {
        assertEquals(
            TrackitNotificationListener.stableId("key", 1L, 12000L, "Shop"),
            TrackitNotificationListener.stableId("key", 1L, 12000L, "Shop")
        )
    }
}
