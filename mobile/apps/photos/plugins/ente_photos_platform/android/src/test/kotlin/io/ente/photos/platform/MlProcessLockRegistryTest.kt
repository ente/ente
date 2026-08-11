package io.ente.photos.platform

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MlProcessLockRegistryTest {
    @After
    fun tearDown() {
        MlProcessLockRegistry.state()?.let {
            MlProcessLockRegistry.resetForInstance(it.pluginInstanceId)
        }
    }

    @Test
    fun concurrentDifferentTokensHaveOneWinner() {
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        val results =
            listOf("first", "second").map { token ->
                executor.submit<Boolean> {
                    ready.countDown()
                    start.await()
                    MlProcessLockRegistry.tryAcquire("instance-$token", token, "fg", "fullRun").acquired
                }
            }

        assertTrue(ready.await(1, TimeUnit.SECONDS))
        start.countDown()
        assertEquals(1, results.count { it.get(1, TimeUnit.SECONDS) })
        executor.shutdownNow()
    }

    @Test
    fun exactOwnerIsIdempotentAndOtherTokensAreDenied() {
        assertTrue(MlProcessLockRegistry.tryAcquire("instance", "token", "fg", "fullRun").acquired)
        assertEquals("fg", MlProcessLockRegistry.state()?.origin)
        assertEquals("fullRun", MlProcessLockRegistry.state()?.operation)
        assertTrue(MlProcessLockRegistry.tryAcquire("instance", "token", "fg", "fullRun").acquired)
        assertFalse(MlProcessLockRegistry.tryAcquire("instance", "other", "fg", "indexing").acquired)
        assertFalse(MlProcessLockRegistry.tryAcquire("other", "token", "bg", "fullRun").acquired)
        assertFalse(MlProcessLockRegistry.release("instance", "other"))
        assertFalse(MlProcessLockRegistry.release("other", "token"))
        assertTrue(MlProcessLockRegistry.release("instance", "token"))
        assertNull(MlProcessLockRegistry.state())
    }

    @Test
    fun resetOnlyReleasesTheCallingInstance() {
        MlProcessLockRegistry.tryAcquire("instance", "token", "bg", "fullRun")
        assertFalse(MlProcessLockRegistry.resetForInstance("other"))
        assertEquals("instance", MlProcessLockRegistry.state()?.pluginInstanceId)
        assertTrue(MlProcessLockRegistry.resetForInstance("instance"))
        assertNull(MlProcessLockRegistry.state())
    }
}
