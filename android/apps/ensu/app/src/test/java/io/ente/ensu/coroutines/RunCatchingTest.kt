package io.ente.ensu.coroutines

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunCatchingTest {
    @Test
    fun cancellationRunsCleanupWithoutExecutingTheFallback() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        var fallback = false
        var cleanedUp = false
        val worker = launch {
            try {
                runCatchingCancellable<Unit> {
                        entered.complete(Unit)
                        awaitCancellation()
                    }
                    .getOrElse { fallback = true }
            } finally {
                cleanedUp = true
            }
        }
        entered.await()
        worker.cancelAndJoin()
        assertTrue(cleanedUp)
        assertFalse(fallback)
    }
}
