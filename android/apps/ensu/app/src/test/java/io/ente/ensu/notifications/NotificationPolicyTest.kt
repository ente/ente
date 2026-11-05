package io.ente.ensu.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationPolicyTest {
    @Test
    fun campaignLimitsPromptsByTimeCountAndAuthorization() {
        val now = 1_000_000L
        assertTrue(canEducate(false, false, 0, null, now))
        assertFalse(canEducate(false, false, 1, now, now + PERMISSION_INTERVAL_MS - 1))
        assertTrue(canEducate(false, false, 1, now, now + PERMISSION_INTERVAL_MS))
        assertTrue(canEducate(false, false, 2, now, now + PERMISSION_INTERVAL_MS))
        assertFalse(canEducate(false, false, 3, now, now + PERMISSION_INTERVAL_MS * 20))
        assertFalse(canEducate(false, false, 1, now, now - 1))
        assertFalse(canEducate(true, false, 0, null, 0))
        assertFalse(canEducate(false, true, 1, 0, PERMISSION_INTERVAL_MS * 20))
    }

    @Test
    fun previewOmitsFormatting() {
        assertEquals(
            "Hello world. Read more.",
            responsePreview("**Hello** *world*. [Read more](https://example.com)."),
        )
        assertEquals("Ready", responsePreview("## Ready"))
        assertEquals("a = 1", responsePreview("```python\na = 1\n```"))
    }

    @Test
    fun titleUsesThirtyVisibleCharactersAndOnlyAddsEllipsisWhenTruncated() {
        assertEquals("A short question?", responseNotificationTitle("A short question?"))
        assertEquals("a".repeat(30), responseNotificationTitle("a".repeat(30)))
        assertEquals("a".repeat(30) + "…", responseNotificationTitle("a".repeat(31)))
        val family = "👨‍👩‍👧‍👦"
        assertEquals(
            "a".repeat(29) + family + "…",
            responseNotificationTitle("a".repeat(29) + family + "?"),
        )
        assertEquals(
            "a".repeat(29) + "e\u0301" + "…",
            responseNotificationTitle("a".repeat(29) + "e\u0301?"),
        )
        assertEquals("Explain this", responseNotificationTitle("  Explain\nthis  "))
        assertEquals("Ensu", responseNotificationTitle("  "))
    }

    @Test
    fun eachAttemptResolvesOnceAndIgnoresStaleCallbacks() {
        for (completeFirst in listOf(false, true)) {
            val lifecycle = ResponseNotificationLifecycle()
            val first = ResponseNotificationAttempt(1, "session", "first", "old query")
            lifecycle.begin(first)
            if (completeFirst) {
                assertEquals(first, lifecycle.resolve(1))
                assertNull(lifecycle.resolve(1))
            }
            assertTrue(lifecycle.clear(1))
            assertNull(lifecycle.resolve(1))
            val retry = ResponseNotificationAttempt(2, "session", "second", "new query")
            lifecycle.begin(retry)
            assertFalse(lifecycle.clear(1))
            assertNull(lifecycle.resolve(1))
            assertEquals(retry, lifecycle.resolve(2))
        }
    }

    @Test
    fun permissionDismissalRemainsRequestableUntilPermanentDenial() {
        val state = NotificationPermissionRequestState()
        assertTrue(state.canRequest(false))
        state.observeRationale(false)
        assertTrue(state.canRequest(false))
        state.observeRationale(true)
        assertTrue(state.canRequest(true))
        state.observeRationale(false)
        assertFalse(state.canRequest(false))
    }
}
