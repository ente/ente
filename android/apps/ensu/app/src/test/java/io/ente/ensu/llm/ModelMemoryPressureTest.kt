package io.ente.ensu.llm

import io.ente.ensu.coroutines.runCatchingCancellable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelMemoryPressureTest {
    @Test
    fun optionalWorkWaitsForBothReleaseAndCooldown() {
        var now = 0L
        val pressure = ModelMemoryPressure { now }
        pressure.requestEviction()
        val eviction = checkNotNull(pressure.pendingEviction())

        now = 60_000
        assertEquals(eviction, pressure.pendingEviction())
        assertTrue(pressure.suppressesOptionalWork())

        pressure.didRelease(eviction)
        assertNull(pressure.pendingEviction())
        assertFalse(pressure.suppressesOptionalWork())
        pressure.requestEviction()
        pressure.didRelease(checkNotNull(pressure.pendingEviction()))

        now = 89_999
        assertTrue(pressure.suppressesOptionalWork())
        now = 90_000
        assertFalse(pressure.suppressesOptionalWork())
    }

    @Test
    fun releasingAnOlderRequestCannotAcknowledgePressureDuringCleanup() {
        var now = 0L
        val pressure = ModelMemoryPressure { now }
        pressure.requestEviction()
        val earlier = checkNotNull(pressure.pendingEviction())
        now = 20_000
        pressure.requestEviction()
        val later = checkNotNull(pressure.pendingEviction())

        pressure.didRelease(earlier)
        assertEquals(later, pressure.pendingEviction())
        pressure.didRelease(later)
        now = 49_999
        assertTrue(pressure.suppressesOptionalWork())
        now = 50_000
        assertFalse(pressure.suppressesOptionalWork())
    }

    @Test
    fun queuedWorkCleansUpBeforeAndAfterAllocation() = runBlocking {
        val mutex = Mutex(locked = true)
        val events = mutableListOf<String>()
        var releaseRequested = false
        var resident = true
        val release = {
            if (releaseRequested && resident) {
                events += "release"
                resident = false
            }
        }
        val operation =
            launch(start = CoroutineStart.UNDISPATCHED) {
                withModelResources(mutex, release) {
                    assertFalse(resident)
                    events += "allocate"
                    resident = true
                }
            }
        releaseRequested = true
        val follower =
            launch(start = CoroutineStart.UNDISPATCHED) { mutex.withLock { assertFalse(resident) } }
        mutex.unlock()
        operation.join()
        follower.join()

        assertEquals(listOf("release", "allocate", "release"), events)
        assertFalse(resident)
    }

    @Test
    fun cancellationWaitsForSynchronousNativeReturnBeforeReleasingContext() = runBlocking {
        val mutex = Mutex()
        val entered = CompletableDeferred<Unit>()
        val nativeReturn = CountDownLatch(1)
        val resident = AtomicBoolean(false)
        val releaseRequested = AtomicBoolean(false)
        val release = { if (releaseRequested.get()) resident.set(false) }
        val operation =
            launch(Dispatchers.Default) {
                withModelResources(mutex, release) {
                    resident.set(true)
                    entered.complete(Unit)
                    check(nativeReturn.await(5, TimeUnit.SECONDS))
                    assertTrue(resident.get())
                }
            }
        try {
            entered.await()
            releaseRequested.set(true)
            operation.cancel()
            val follower =
                launch(start = CoroutineStart.UNDISPATCHED) {
                    mutex.withLock { assertFalse(resident.get()) }
                }
            assertFalse(operation.isCompleted)
            assertFalse(follower.isCompleted)
            assertTrue(resident.get())
            nativeReturn.countDown()
            operation.join()
            follower.join()
            assertFalse(resident.get())
        } finally {
            nativeReturn.countDown()
            operation.cancelAndJoin()
        }
    }

    @Test
    fun failedWorkReleasesResourcesBeforeUnlocking() = runBlocking {
        val mutex = Mutex()
        var resident = false
        val result = runCatchingCancellable {
            withModelResources(mutex, { resident = false }) {
                resident = true
                error("Native operation failed")
            }
        }
        assertTrue(result.exceptionOrNull() is IllegalStateException)
        assertFalse(resident)
        assertFalse(mutex.isLocked)
    }
}
