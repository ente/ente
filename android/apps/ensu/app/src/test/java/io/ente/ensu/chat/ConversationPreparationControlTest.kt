package io.ente.ensu.chat

import io.ente.ensu.bindings.ConversationPreparation
import io.ente.ensu.bindings.NoHandle
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConversationPreparationControlTest {
    @Test
    fun cancellationAfterCloseDoesNotReachDestroyedWork() {
        val work = RecordingPreparation()
        val control = ConversationPreparationControl(work)

        control.close()
        control.cancel()
        control.close()

        assertEquals(1, work.cancelCalls.get())
        assertEquals(1, work.destroyCalls.get())
    }

    @Test
    fun closeWaitsForCancellationAlreadyInProgress() {
        val cancelEntered = CountDownLatch(1)
        val releaseCancel = CountDownLatch(1)
        val closeStarted = CountDownLatch(1)
        val closeFinished = CountDownLatch(1)
        val work = RecordingPreparation { call ->
            if (call == 1) {
                cancelEntered.countDown()
                assertTrue(releaseCancel.await(5, TimeUnit.SECONDS))
            }
        }
        val control = ConversationPreparationControl(work)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val cancellation = executor.submit { control.cancel() }
            assertTrue(cancelEntered.await(5, TimeUnit.SECONDS))
            val cleanup = executor.submit {
                closeStarted.countDown()
                control.close()
                closeFinished.countDown()
            }
            assertTrue(closeStarted.await(5, TimeUnit.SECONDS))
            assertFalse(closeFinished.await(100, TimeUnit.MILLISECONDS))
            assertEquals(0, work.destroyCalls.get())

            releaseCancel.countDown()
            cancellation.get(5, TimeUnit.SECONDS)
            cleanup.get(5, TimeUnit.SECONDS)
            assertEquals(2, work.cancelCalls.get())
            assertEquals(1, work.destroyCalls.get())
        } finally {
            releaseCancel.countDown()
            executor.shutdownNow()
        }
    }

    private class RecordingPreparation(private val onCancel: (Int) -> Unit = {}) :
        ConversationPreparation(NoHandle) {
        val cancelCalls = AtomicInteger()
        val destroyCalls = AtomicInteger()
        private val destroyed = AtomicBoolean()

        override fun cancel() {
            check(!destroyed.get()) { "Preparation was already destroyed" }
            onCancel(cancelCalls.incrementAndGet())
            check(!destroyed.get()) { "Preparation was destroyed during cancellation" }
        }

        override fun destroy() {
            destroyed.set(true)
            destroyCalls.incrementAndGet()
            super.destroy()
        }
    }
}
