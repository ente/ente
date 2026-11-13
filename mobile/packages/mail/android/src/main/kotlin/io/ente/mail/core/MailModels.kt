package io.ente.mail.core

import java.io.File

enum class MailUnavailableReason {
    NO_MAIL_CLIENT,
    ATTACHMENT_COMPOSER_UNAVAILABLE,
    ATTACHMENT_MISSING,
    ATTACHMENT_UNREADABLE,
    ATTACHMENT_TOO_LARGE,
    COMPOSER_BUSY,
    PRESENTATION_FAILED
}

sealed interface MailResult {
    data object Launched : MailResult
    data class Unavailable(val reason: MailUnavailableReason) : MailResult
}

data class MailAttachment(
    val path: String,
    val mimeType: String
) {
    init {
        require(File(path).isAbsolute) { "Attachment path must be absolute" }
        require(MIME_TYPE.matches(mimeType)) { "Attachment MIME type is invalid" }
        require(File(path).name.isSafeFileName()) { "Attachment filename is invalid" }
    }

    private companion object {
        val MIME_TYPE = Regex("^[A-Za-z0-9!#\\$&^_.+-]+/[A-Za-z0-9!#\\$&^_.+-]+$")
    }
}

data class MailRequest(
    val recipient: String,
    val subject: String,
    val body: String,
    val attachment: MailAttachment?
) {
    init {
        require(recipient.isNotEmpty() && recipient == recipient.trim()) {
            "Recipient is invalid"
        }
        require(listOf(recipient, subject, body).none { '\u0000' in it }) {
            "Mail text contains a null byte"
        }
    }
}

private fun String.isSafeFileName(): Boolean =
    isNotEmpty() &&
        this != "." &&
        this != ".." &&
        '/' !in this &&
        '\\' !in this &&
        none { it.code < 0x20 || it.code == 0x7f }
