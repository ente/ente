package io.ente.ensu.chat

import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.MaxImageAttachmentsPerMessage
import io.ente.ensu.AppState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import java.io.File

internal class AttachmentStoreActions(
    private val state: MutableStateFlow<AppState>,
    private val messageStore: MutableMap<String, MutableList<ChatMessage>>
) {
    fun setAttachmentProcessing(isProcessing: Boolean) {
        state.update { appState ->
            appState.copy(chat = appState.chat.copy(isProcessingAttachments = isProcessing))
        }
    }

    fun addAttachment(attachment: Attachment) {
        var accepted = false
        state.update { appState ->
            val chat = appState.chat
            val imageLimitReached = attachment.type == AttachmentType.Image &&
                chat.attachments.count { it.type == AttachmentType.Image } >=
                MaxImageAttachmentsPerMessage
            if (chat.isGenerating ||
                chat.isDownloading ||
                imageLimitReached
            ) {
                appState.copy(
                    chat = chat.copy(isProcessingAttachments = false)
                )
            } else {
                accepted = true
                appState.copy(
                    chat = chat.copy(
                        attachments = chat.attachments + attachment,
                        isProcessingAttachments = false
                    )
                )
            }
        }
        if (!accepted) deleteIfUnstored(attachment)
    }

    fun removeAttachment(attachment: Attachment) {
        state.update { appState ->
            appState.copy(
                chat = appState.chat.copy(
                    attachments = appState.chat.attachments.filterNot { it.id == attachment.id }
                )
            )
        }
        deleteIfUnstored(attachment)
    }

    fun discardAttachments(attachments: List<Attachment>) {
        attachments.forEach(::deleteIfUnstored)
    }

    private fun deleteIfUnstored(attachment: Attachment) {
        val stored = messageStore.values.any { messages ->
            messages.any { message -> message.attachments.any { it.id == attachment.id } }
        }
        if (!stored) attachment.localPath?.let { File(it).delete() }
    }
}
