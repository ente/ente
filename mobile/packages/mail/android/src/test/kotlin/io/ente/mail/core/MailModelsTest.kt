package io.ente.mail.core

import org.junit.Assert.assertThrows
import org.junit.Test

class MailModelsTest {
    @Test
    fun `requires explicit valid attachment metadata`() {
        assertThrows(IllegalArgumentException::class.java) {
            MailAttachment("relative.zip", "application/zip")
        }
        assertThrows(IllegalArgumentException::class.java) {
            MailAttachment("/tmp/logs.zip", "zip")
        }
        assertThrows(IllegalArgumentException::class.java) {
            MailAttachment("/", "application/zip")
        }
    }
}
