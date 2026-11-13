package io.ente.ensu

import java.nio.ByteBuffer

internal fun ByteArray.toDirectByteBuffer(): ByteBuffer =
    ByteBuffer.allocateDirect(size).put(this).apply { flip() }
