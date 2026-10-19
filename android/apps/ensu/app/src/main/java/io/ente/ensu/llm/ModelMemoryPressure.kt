package io.ente.ensu.llm

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal class ModelMemoryPressure(private val elapsedRealtime: () -> Long) {
    private var requestedGeneration = 0L
    private var releasedGeneration = 0L
    private var retryAfter = 0L

    @Synchronized
    fun requestEviction() {
        requestedGeneration++
        retryAfter = elapsedRealtime() + COOLDOWN_MILLIS
    }

    @Synchronized
    fun suppressesOptionalWork(): Boolean =
        requestedGeneration != releasedGeneration || elapsedRealtime() < retryAfter

    @Synchronized
    fun remainingCooldownMillis(): Long = (retryAfter - elapsedRealtime()).coerceAtLeast(0)

    @Synchronized
    fun pendingEviction(): Long? = requestedGeneration.takeIf { it != releasedGeneration }

    @Synchronized
    fun didRelease(generation: Long) {
        releasedGeneration = maxOf(releasedGeneration, generation)
    }

    private companion object {
        const val COOLDOWN_MILLIS = 30_000L
    }
}

internal sealed interface ChatWarmupResult {
    data object Ready : ChatWarmupResult

    data object Skipped : ChatWarmupResult

    data class RetryAfter(val millis: Long) : ChatWarmupResult
}

internal suspend fun retryChatWarmup(
    isEligible: () -> Boolean,
    wait: suspend (Long) -> Unit = { delay(it) },
    operation: suspend () -> ChatWarmupResult,
): Boolean {
    while (true) {
        currentCoroutineContext().ensureActive()
        if (!isEligible()) return false
        val result = operation()
        currentCoroutineContext().ensureActive()
        when (result) {
            ChatWarmupResult.Ready -> return true
            ChatWarmupResult.Skipped -> return false
            is ChatWarmupResult.RetryAfter -> {
                if (result.millis <= 0) return false
                wait(result.millis)
            }
        }
    }
}

internal suspend fun <T> withModelResources(
    mutex: Mutex,
    releaseIfNeeded: () -> Unit,
    block: suspend () -> T,
): T = mutex.withLock {
    releaseIfNeeded()
    try {
        block()
    } finally {
        releaseIfNeeded()
    }
}
