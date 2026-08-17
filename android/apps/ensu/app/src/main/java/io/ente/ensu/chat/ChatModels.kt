package io.ente.ensu.chat

import java.util.UUID

enum class MessageAuthor {
    User,
    Assistant
}

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val sessionId: String,
    val parentId: String? = null,
    val author: MessageAuthor,
    val text: String,
    val timestampMillis: Long,
    val attachments: List<Attachment> = emptyList(),
    val isInterrupted: Boolean = false,
    val isSynthetic: Boolean = false,
    val tokensPerSecond: Double? = null,
    val branchCount: Int = 1
)

data class ChatSession(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val lastMessagePreview: String? = null,
    val updatedAtMillis: Long
)

enum class AttachmentType {
    Image,
    Document
}

const val MaxImageAttachmentsPerMessage = 2

data class Attachment(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val sizeBytes: Long,
    val type: AttachmentType,
    val localPath: String? = null,
    val isUploading: Boolean = false
)

const val SessionTitleMaxLength = 40

fun sessionTitleFromText(text: String, fallback: String = "New Chat"): String {
    val trimmed = sanitizeTitleText(text)
    if (trimmed.isBlank()) return fallback
    return if (trimmed.length <= SessionTitleMaxLength) {
        trimmed
    } else {
        trimmed.take(SessionTitleMaxLength).trimEnd() + "…"
    }
}

private val TitleLineBreakRegex = Regex("[\r\n\t]+")
private val TitleWhitespaceRegex = Regex("\\s+")

internal fun sanitizeTitleText(text: String): String {
    return text
        .replace(TitleLineBreakRegex, " ")
        .replace(TitleWhitespaceRegex, " ")
        .trim()
}
