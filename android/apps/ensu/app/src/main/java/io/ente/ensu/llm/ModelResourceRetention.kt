package io.ente.ensu.llm

import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext

internal class ModelResourceRetention {
    private val requests = MutableStateFlow(0)

    val isActive: Boolean
        get() = requests.value > 0

    fun shouldReleaseIdleCache(
        appForeground: Boolean,
        chatForeground: Boolean,
        expiresAt: Long,
        now: Long,
    ): Boolean =
        !isActive && now >= expiresAt && (!appForeground || (expiresAt > 0 && !chatForeground))

    suspend fun awaitIdle() {
        requests.first { it == 0 }
    }

    suspend fun <T> retain(release: suspend () -> Unit, block: suspend () -> T): T {
        requests.update { it + 1 }
        try {
            return block()
        } finally {
            requests.update { it - 1 }
            withContext(NonCancellable) { release() }
        }
    }
}
