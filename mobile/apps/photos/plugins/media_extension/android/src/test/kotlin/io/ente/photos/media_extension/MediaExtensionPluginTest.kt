package io.ente.photos.media_extension

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MediaExtensionPluginTest {
    @Test
    fun matchesSupportedMediaProviderPendingMessages() {
        val messages = listOf(
            "Only owner is able to interact with pending media content://media/item",
            "Only owner is able to interact with pending item content://media/item",
            "Only owner is able to interact with pending/trashed item content://media/item",
        )

        for (message in messages) {
            assertTrue(isMediaStorePendingItemError(message), message)
        }
    }

    @Test
    fun rejectsUnrelatedMediaProviderErrors() {
        assertFalse(isMediaStorePendingItemError(null))
        assertFalse(isMediaStorePendingItemError("Permission denied"))
    }
}
