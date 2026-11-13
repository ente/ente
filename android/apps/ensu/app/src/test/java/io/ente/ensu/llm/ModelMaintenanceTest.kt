package io.ente.ensu.llm

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelMaintenanceTest {
    @Test
    fun leavingChatWaitsForActiveModelWorkBeforeUnloading() = runBlocking {
        val mutex = Mutex(locked = true)
        var resident = true
        val release =
            launch(start = CoroutineStart.UNDISPATCHED) {
                releaseInactiveChatResources(mutex, { false }) { resident = false }
            }

        assertFalse(release.isCompleted)
        assertTrue(resident)
        mutex.unlock()
        release.join()
        assertFalse(resident)
    }

    @Test
    fun returningToChatBeforeQueuedReleaseKeepsTheModelLoaded() = runBlocking {
        val mutex = Mutex(locked = true)
        var chatForeground = false
        var resident = true
        val release =
            launch(start = CoroutineStart.UNDISPATCHED) {
                releaseInactiveChatResources(mutex, { chatForeground }) { resident = false }
            }

        chatForeground = true
        mutex.unlock()
        release.join()
        assertTrue(resident)
    }

    @Test
    fun openingAttachmentPickerBeforeQueuedReleaseKeepsTheModelLoaded() = runBlocking {
        val mutex = Mutex(locked = true)
        var pickerPending = false
        var resident = true
        val release =
            launch(start = CoroutineStart.UNDISPATCHED) {
                releaseInactiveChatResources(mutex, { false }, { pickerPending }) {
                    resident = false
                }
            }

        pickerPending = true
        mutex.unlock()
        release.join()
        assertTrue(resident)
    }
}
