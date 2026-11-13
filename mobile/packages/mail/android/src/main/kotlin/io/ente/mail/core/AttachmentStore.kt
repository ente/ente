package io.ente.mail.core

import java.io.File
import java.io.IOException
import java.util.UUID

class AttachmentStore(
    private val root: File,
    private val maximumBytes: Long = MAXIMUM_BYTES,
    private val now: () -> Long = System::currentTimeMillis
) {
    sealed interface StageResult {
        data class Staged(val directory: File, val file: File) : StageResult
        data class Unavailable(val reason: MailUnavailableReason) : StageResult
    }

    fun stage(attachment: MailAttachment): StageResult {
        val source = File(attachment.path)
        if (!source.exists()) {
            return StageResult.Unavailable(MailUnavailableReason.ATTACHMENT_MISSING)
        }
        if (!source.isFile || !source.canRead()) {
            return StageResult.Unavailable(MailUnavailableReason.ATTACHMENT_UNREADABLE)
        }
        val sourceLength = source.length()
        if (sourceLength > maximumBytes) {
            return StageResult.Unavailable(MailUnavailableReason.ATTACHMENT_TOO_LARGE)
        }

        val directory = File(root, UUID.randomUUID().toString())
        return try {
            check(directory.mkdirs()) { "Could not create mail attachment directory" }
            val destination = File(directory, source.name)
            source.inputStream().use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var copied = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > maximumBytes) throw AttachmentTooLargeException()
                        output.write(buffer, 0, count)
                    }
                }
            }
            if (destination.length() != sourceLength) {
                throw IOException("Attachment changed while being copied")
            }
            directory.setLastModified(now())
            StageResult.Staged(directory, destination)
        } catch (_: AttachmentTooLargeException) {
            directory.deleteRecursively()
            StageResult.Unavailable(MailUnavailableReason.ATTACHMENT_TOO_LARGE)
        } catch (_: Exception) {
            directory.deleteRecursively()
            StageResult.Unavailable(MailUnavailableReason.ATTACHMENT_UNREADABLE)
        }
    }

    fun discard(staged: StageResult.Staged) {
        staged.directory.deleteRecursively()
    }

    fun pruneExpired(retentionMs: Long = RETENTION_MS) {
        val cutoff = now() - retentionMs
        root.listFiles()?.forEach { entry ->
            if (entry.lastModified() < cutoff) entry.deleteRecursively()
        }
    }

    companion object {
        const val MAXIMUM_BYTES = 20 * 1024 * 1024L
        const val RETENTION_MS = 24 * 60 * 60 * 1000L
    }
}

private class AttachmentTooLargeException : IOException()
