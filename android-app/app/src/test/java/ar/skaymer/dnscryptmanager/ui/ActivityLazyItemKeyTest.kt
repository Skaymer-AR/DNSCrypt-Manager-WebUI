package ar.skaymer.dnscryptmanager.ui

import ar.skaymer.dnscryptmanager.ActivityEvent
import org.junit.Assert.assertEquals
import org.junit.Test

class ActivityLazyItemKeyTest {
    @Test
    fun duplicateEventsHaveDistinctLazyListKeys() {
        val event = ActivityEvent(
            time = "[2026-09-30 10:00:00]",
            domain = "updates.example.com",
            status = "blocked",
            rule = "updates.example.com",
            category = "security",
            returnCode = "NOERROR",
            duration = "2ms",
        )

        val keys = listOf(event, event).mapIndexed(::activityLazyItemKey)

        assertEquals(2, keys.distinct().size)
    }
}
