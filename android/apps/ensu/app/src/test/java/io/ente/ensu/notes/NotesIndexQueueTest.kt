package io.ente.ensu.notes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class NotesIndexQueueTest {
    @Test
    fun manualRequestsTakePriorityCoalesceAndClearDeferral() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("automatic", immediate = true)
        queue.enqueue("selected", forced = setOf("edited.md"), changesDetected = true)
        assertEquals("automatic", queue.next(emptySet())?.key)
        assertFalse(queue.updateNow("automatic"))
        assertTrue(queue.updateNow("selected"))
        val snapshot = requireNotNull(queue.next(emptySet()))
        assertEquals("selected", snapshot.key)
        assertEquals(NotesStatus.UpdateRequested, snapshot.value.trigger.waitingStatus)
        assertTrue(queue.updateNow("selected"))
        assertSame(snapshot.value, queue["selected"])

        queue.defer("selected")
        assertEquals("automatic", queue.next(emptySet())?.key)
        assertTrue(queue.updateNow("selected"))
        val resumed = requireNotNull(queue.next(emptySet())).value
        assertEquals(setOf("edited.md"), resumed.forced)
        assertEquals(NotesIndexTrigger.Manual, resumed.trigger)
        queue.finish("selected", resumed)
        assertNull(queue["selected"])
        assertFalse(queue.updateNow("selected"))
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
    fun retriesPromoteFailuresAndPreserveChangesArrivingDuringTheAttempt() {
        val queue = NotesIndexQueue { 100 }
        queue.enqueue("automatic", forced = setOf("first.md"), changesDetected = true)
        for (id in listOf("automatic", "initial")) {
            queue.retry(id)
            val snapshot = requireNotNull(queue.next(emptySet())).value
            assertEquals(NotesIndexTrigger.Manual, snapshot.trigger)
            queue.enqueue(id, forced = setOf("second.md"), rebuild = true)
            queue.finish(id, snapshot)
            assertNull(queue.next(setOf(id)))
            queue.retry(id)

            val retry = requireNotNull(queue.next(emptySet())).value
            assertEquals(NotesIndexTrigger.Manual, retry.trigger)
            assertEquals(snapshot.forced + "second.md", retry.forced)
            assertTrue(retry.rebuild)
            queue.finish(id, retry)
            assertNull(queue[id])
        }
    }
}
