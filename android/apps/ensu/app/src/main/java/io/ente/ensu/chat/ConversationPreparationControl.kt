package io.ente.ensu.chat

import io.ente.ensu.bindings.ConversationPreparation

internal class ConversationPreparationControl(preparation: ConversationPreparation) :
    AutoCloseable {
    private var preparation: ConversationPreparation? = preparation

    @Synchronized
    fun cancel() {
        preparation?.cancel()
    }

    @Synchronized
    override fun close() {
        val current = preparation ?: return
        preparation = null
        try {
            current.cancel()
        } finally {
            current.destroy()
        }
    }
}
