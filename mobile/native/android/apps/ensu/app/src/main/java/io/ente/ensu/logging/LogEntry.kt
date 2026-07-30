package io.ente.ensu.logging

import java.util.UUID

data class LogEntry(
    val id: String,
    val timestampMillis: Long,
    val level: LogLevel,
    val tag: String? = null,
    val message: String,
    val details: String? = null
)

enum class LogLevel {
    Info,
    Warning,
    Error
}

internal fun buildLogEntry(
    level: LogLevel,
    message: String,
    details: String?,
    tag: String?,
    throwable: Throwable?,
    idProvider: () -> String = { UUID.randomUUID().toString() },
    nowProvider: () -> Long = { System.currentTimeMillis() }
): LogEntry {
    val combinedDetails = buildString {
        if (!details.isNullOrBlank()) {
            append(details)
        }
        if (throwable != null) {
            if (isNotEmpty()) append("\n")
            append(throwable.stackTraceToString())
        }
    }.ifBlank { null }

    val safeMessage = sanitizeLog(message).orEmpty()
    val safeDetails = sanitizeLog(combinedDetails)

    return LogEntry(
        id = idProvider(),
        timestampMillis = nowProvider(),
        level = level,
        tag = tag,
        message = safeMessage,
        details = safeDetails
    )
}
