package io.ente.ensu.device

const val CHAT_MIN_RAM_BYTES: Long = 1_600_000_000L

internal fun chatDeviceCapability(totalMemoryBytes: Long): ChatDeviceCapability =
    when {
        totalMemoryBytes <= 0 -> ChatDeviceCapability.Unknown
        totalMemoryBytes < CHAT_MIN_RAM_BYTES ->
            ChatDeviceCapability.UnsupportedLowMemory(totalMemoryBytes, CHAT_MIN_RAM_BYTES)
        else -> ChatDeviceCapability.Supported(totalMemoryBytes)
    }

sealed interface ChatDeviceCapability {
    val totalMemoryBytes: Long?

    data class Supported(override val totalMemoryBytes: Long?) : ChatDeviceCapability

    data class UnsupportedLowMemory(
        override val totalMemoryBytes: Long,
        val requiredMemoryBytes: Long,
    ) : ChatDeviceCapability

    object Unknown : ChatDeviceCapability {
        override val totalMemoryBytes: Long? = null
    }
}

class UnsupportedDeviceMemoryException(val capability: ChatDeviceCapability.UnsupportedLowMemory) :
    IllegalStateException("Device does not have enough RAM for local chat")

fun ChatDeviceCapability.isChatSupported(): Boolean =
    this !is ChatDeviceCapability.UnsupportedLowMemory

fun ChatDeviceCapability.requireChatSupported() {
    if (this is ChatDeviceCapability.UnsupportedLowMemory) {
        throw UnsupportedDeviceMemoryException(this)
    }
}
