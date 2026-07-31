package io.ente.ensu

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AttachmentInputTest {
    @Test
    fun acceptsInputAtTheLimit() {
        val input = byteArrayOf(1, 2, 3, 4)

        val result = ByteArrayInputStream(input).readAttachmentImageBytes(maxBytes = input.size)

        assertArrayEquals(input, result)
    }

    @Test
    fun rejectsInputPastTheLimit() {
        val input = ByteArrayInputStream(byteArrayOf(1, 2, 3, 4, 5))

        assertThrows(IOException::class.java) {
            input.readAttachmentImageBytes(maxBytes = 4)
        }
    }

    @Test
    fun stopsReadingAStreamThatDoesNotEnd() {
        val input = object : InputStream() {
            override fun read(): Int = 0

            override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                buffer.fill(0, offset, offset + length)
                return length
            }
        }

        assertThrows(IOException::class.java) {
            input.readAttachmentImageBytes(maxBytes = 16)
        }
    }
}
