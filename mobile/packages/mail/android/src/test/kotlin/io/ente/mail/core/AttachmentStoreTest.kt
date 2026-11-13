package io.ente.mail.core

import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentStoreTest {
    @Test
    fun `stages attachment in an isolated session`() {
        val temporary = Files.createTempDirectory("ente-mail-test").toFile()
        try {
            val source = temporary.resolve("source.zip").apply {
                writeBytes(byteArrayOf(1, 2, 3))
            }
            val store = AttachmentStore(temporary.resolve("mail"))

            val result = store.stage(
                MailAttachment(source.absolutePath, "application/zip")
            )

            assertTrue(result is AttachmentStore.StageResult.Staged)
            result as AttachmentStore.StageResult.Staged
            assertEquals("source.zip", result.file.name)
            assertArrayEquals(source.readBytes(), result.file.readBytes())
            assertTrue(result.file.canonicalPath.startsWith(
                temporary.resolve("mail").canonicalPath
            ))
        } finally {
            temporary.deleteRecursively()
        }
    }

    @Test
    fun `rejects unusable attachments and prunes expired sessions`() {
        var now = 2 * AttachmentStore.RETENTION_MS
        val temporary = Files.createTempDirectory("ente-mail-test").toFile()
        try {
            val store = AttachmentStore(temporary.resolve("mail")) { now }
            val missing = store.stage(
                MailAttachment(
                    temporary.resolve("missing.zip").absolutePath,
                    "application/zip"
                )
            )
            assertEquals(
                MailUnavailableReason.ATTACHMENT_MISSING,
                (missing as AttachmentStore.StageResult.Unavailable).reason
            )

            val oversizedFile = temporary.resolve("oversized.zip").apply {
                writeBytes(byteArrayOf(1, 2, 3))
            }
            val oversized = AttachmentStore(
                temporary.resolve("mail"),
                maximumBytes = 2
            ).stage(
                MailAttachment(
                    oversizedFile.absolutePath,
                    "application/zip"
                )
            )
            assertEquals(
                MailUnavailableReason.ATTACHMENT_TOO_LARGE,
                (oversized as AttachmentStore.StageResult.Unavailable).reason
            )

            val expired = temporary.resolve("mail/expired").apply {
                mkdirs()
                setLastModified(0)
            }
            val current = temporary.resolve("mail/current").apply {
                mkdirs()
                setLastModified(now)
            }
            now += 1
            store.pruneExpired()

            assertFalse(expired.exists())
            assertTrue(current.exists())
        } finally {
            temporary.deleteRecursively()
        }
    }
}
