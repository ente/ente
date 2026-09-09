package io.ente.ensu.notes

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

internal suspend fun <T> runNotesRead(cancel: () -> Unit, read: () -> T): T = coroutineScope {
    val worker = async(Dispatchers.IO) {
        try {
            read()
        } catch (error: Exception) {
            currentCoroutineContext().ensureActive()
            throw error
        }
    }
    try {
        worker.await()
    } finally {
        try {
            cancel()
        } finally {
            withContext(NonCancellable) { worker.join() }
        }
    }
}
