package io.ente.ensu.llm

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelResourceRetentionTest {
    @Test
    fun retainedCacheExpiresInSettingsButStaysAvailableToChat() {
        val resources = ModelResourceRetention()
        val deadline = 60_000L
        assertFalse(resources.shouldReleaseIdleCache(false, false, deadline, deadline - 1))
        assertFalse(resources.shouldReleaseIdleCache(true, false, deadline, deadline - 1))
        assertTrue(resources.shouldReleaseIdleCache(true, false, deadline, deadline))
        assertTrue(resources.shouldReleaseIdleCache(false, false, deadline, deadline))
        assertFalse(resources.shouldReleaseIdleCache(true, true, deadline, deadline))
        assertFalse(resources.shouldReleaseIdleCache(true, false, 0, deadline))
    }

    @Test
    fun resourcesStayUntilTheReplacementFinishesCancellationCleanup() = runBlocking {
        val resources = ModelResourceRetention()
        var resident = true
        val release: suspend () -> Unit = {
            yield()
            if (resources.shouldReleaseIdleCache(false, false, 0, 0)) resident = false
        }
        val finish = CompletableDeferred<Unit>()
        val older =
            launch(start = CoroutineStart.UNDISPATCHED) {
                resources.retain(release) { finish.await() }
            }
        val replacement =
            launch(start = CoroutineStart.UNDISPATCHED) {
                resources.retain(release) { awaitCancellation() }
            }

        val idle = async(start = CoroutineStart.UNDISPATCHED) { resources.awaitIdle() }

        finish.complete(Unit)
        older.join()
        assertTrue(resources.isActive)
        assertTrue(resident)
        assertFalse(idle.isCompleted)
        replacement.cancelAndJoin()
        assertFalse(resources.isActive)
        assertFalse(resident)
        idle.await()
    }
}
