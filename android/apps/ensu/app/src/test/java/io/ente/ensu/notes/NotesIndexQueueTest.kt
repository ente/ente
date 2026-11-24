package io.ente.ensu.notes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class NotesIndexQueueTest {
    @Test
    fun retryPromotesAutomaticAndInitialFailuresToManualWork() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("automatic", changesDetected = true)
        for (id in listOf("automatic", "initial")) {
            queue.retry(id)
            val retry = requireNotNull(queue.next(emptySet()))
            assertEquals(id, retry.key)
            assertEquals(NotesIndexTrigger.Manual, retry.value.trigger)
            queue.finish(id, retry.value)
        }
    }

    @Test
    fun editsDiscoveredAfterCompletionNeedANewManualRequest() {
        var now = 100L
        val queue = NotesIndexQueue { now }
        queue.enqueue("selected", changesDetected = true)
        queue.updateNow("selected")
        queue.finish("selected", requireNotNull(queue["selected"]))
        queue.enqueue("selected", forced = setOf("edited.md"), changesDetected = true)
        assertNull(queue.next(emptySet()))
        assertEquals(NotesStatus.UpdateScheduled, queue["selected"]?.trigger?.waitingStatus)
        now += 300_000
        assertEquals("selected", queue.next(emptySet())?.key)
    }

    @Test
    fun manualUpdateBypassesDelayAndRunsBeforeAutomaticWork() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("automatic", immediate = true)
        queue.enqueue("selected", changesDetected = true)
        queue.defer("selected")
        assertEquals(NotesStatus.UpdateScheduled, queue["selected"]?.trigger?.waitingStatus)
        assertEquals("automatic", queue.next(emptySet())?.key)

        assertTrue(queue.updateNow("selected"))
        assertEquals("selected", queue.next(emptySet())?.key)
        assertEquals(NotesStatus.UpdateRequested, queue["selected"]?.trigger?.waitingStatus)
        assertFalse(queue.updateNow("automatic"))
    }

    @Test
    fun repeatedManualRequestsKeepOneQueuedUpdateAndCanClearDeferral() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("selected", forced = setOf("edited.md"), changesDetected = true)
        assertTrue(queue.updateNow("selected"))
        val snapshot = requireNotNull(queue["selected"])
        assertTrue(queue.updateNow("selected"))
        assertSame(snapshot, queue["selected"])

        queue.defer("selected")
        assertNull(queue.next(emptySet()))
        assertTrue(queue.updateNow("selected"))
        val resumed = requireNotNull(queue.next(emptySet())).value
        assertEquals(setOf("edited.md"), resumed.forced)
        assertEquals(NotesIndexTrigger.Manual, resumed.trigger)
        queue.finish("selected", resumed)
        assertNull(queue.next(emptySet()))
        assertFalse(queue.updateNow("selected"))
    }

    @Test
    fun retryPreservesManualIntentAndMergedDocumentChanges() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("selected", forced = setOf("first.md"), changesDetected = true)
        queue.updateNow("selected")
        val snapshot = requireNotNull(queue["selected"])
        queue.enqueue("selected", forced = setOf("second.md"), rebuild = true)
        queue.finish("selected", snapshot)
        assertNull(queue.next(setOf("selected")))
        queue.retry("selected")

        val retry = requireNotNull(queue.next(emptySet())).value
        assertEquals(NotesIndexTrigger.Manual, retry.trigger)
        assertEquals(setOf("first.md", "second.md"), retry.forced)
        assertTrue(retry.rebuild)
        queue.finish("selected", retry)
        assertNull(queue["selected"])
    }
}
