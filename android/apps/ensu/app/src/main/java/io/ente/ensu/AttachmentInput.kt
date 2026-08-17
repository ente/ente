package io.ente.ensu

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

internal const val MaxAttachmentImageInputBytes = 32 * 1024 * 1024

internal fun InputStream.readAttachmentImageBytes(
    maxBytes: Int = MaxAttachmentImageInputBytes
): ByteArray {
    require(maxBytes >= 0) { "maxBytes must not be negative" }

    val output = ByteArrayOutputStream(minOf(DEFAULT_BUFFER_SIZE, maxBytes))
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var totalBytes = 0

    while (true) {
        val bytesRead = read(buffer)
        if (bytesRead < 0) break
        if (bytesRead == 0) continue
        if (bytesRead > maxBytes - totalBytes) {
            throw IOException("Image attachment exceeds the $maxBytes-byte limit")
        }
        output.write(buffer, 0, bytesRead)
        totalBytes += bytesRead
    }

    return output.toByteArray()
}
