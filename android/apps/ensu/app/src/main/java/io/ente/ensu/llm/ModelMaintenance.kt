package io.ente.ensu.llm

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface ModelMaintenance {
    fun suspendMaintenance(): AutoCloseable

    suspend fun awaitMaintenance()

    fun modelReadinessChanged()
}

internal suspend fun <T> ModelMaintenance?.withMaintenanceSuspended(block: suspend () -> T): T {
    val token = this?.suspendMaintenance()
    try {
        this?.awaitMaintenance()
        return block()
    } finally {
        token?.close()
    }
}

internal suspend fun releaseInactiveChatResources(
    mutex: Mutex,
    isChatForeground: () -> Boolean,
    isPickerPending: () -> Boolean = { false },
    release: () -> Unit,
) = mutex.withLock { if (!isChatForeground() && !isPickerPending()) release() }
