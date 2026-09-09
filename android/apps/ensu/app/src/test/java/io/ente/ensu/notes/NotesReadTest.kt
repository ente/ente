package io.ente.ensu.notes

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotesReadTest {
    @Test
    fun ownerCancellationKeepsResourcesUntilTheWorkerDrains() = runBlocking {
        val owner = Job()
        val entered = CountDownLatch(1)
        val cancelled = CountDownLatch(1)
        val drain = CountDownLatch(1)
        val released = AtomicBoolean()
        launch(owner) {
            try {
                runNotesRead(cancelled::countDown) {
                    entered.countDown()
                    check(drain.await(5, TimeUnit.SECONDS))
                }
            } finally {
                released.set(true)
            }
        }

        try {
            assertTrue(withContext(Dispatchers.IO) { entered.await(5, TimeUnit.SECONDS) })
            owner.cancel()
            assertTrue(withContext(Dispatchers.IO) { cancelled.await(5, TimeUnit.SECONDS) })
            assertFalse(released.get())
        } finally {
            drain.countDown()
            owner.cancelAndJoin()
        }

        assertTrue(released.get())
    }
}
