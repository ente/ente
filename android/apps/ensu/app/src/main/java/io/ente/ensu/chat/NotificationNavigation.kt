package io.ente.ensu.chat

import io.ente.ensu.bindings.DbException
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.job

internal class NotificationNavigation(private val onLoadFailure: (DbException) -> Unit) {
    private var pending: Job? = null
    private val _opened = MutableStateFlow<String?>(null)
    val opened = _opened.asStateFlow()

    suspend fun open(load: suspend () -> Boolean) = coroutineScope {
        cancel()
        val job = coroutineContext.job
        pending = job
        try {
            if (load()) _opened.value = UUID.randomUUID().toString()
        } catch (error: DbException) {
            coroutineContext.ensureActive()
            onLoadFailure(error)
        } finally {
            if (pending === job) pending = null
        }
    }

    fun cancel() {
        pending?.cancel()
        pending = null
        _opened.value = null
    }

    fun acknowledge(token: String) {
        _opened.compareAndSet(token, null)
    }
}
