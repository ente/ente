package io.ente.ensu.device

// Compared against the memory the OS reports (ActivityManager.totalMem), which runs
// well below marketed RAM. 3.2 GB sits in the gap between 3 GB devices (~2.7-3.0 GB
// reported) and 4 GB devices (~3.4-3.8 GB reported), so 4 GB devices pass and 3 GB don't.
const val CHAT_MIN_RAM_BYTES: Long = 3_200_000_000L

sealed interface ChatDeviceCapability {
    val totalMemoryBytes: Long?

    data class Supported(
        override val totalMemoryBytes: Long?
    ) : ChatDeviceCapability

    data class UnsupportedLowMemory(
        override val totalMemoryBytes: Long,
        val requiredMemoryBytes: Long = CHAT_MIN_RAM_BYTES
    ) : ChatDeviceCapability

    object Unknown : ChatDeviceCapability {
        override val totalMemoryBytes: Long? = null
    }
}


class UnsupportedDeviceMemoryException(
    val capability: ChatDeviceCapability.UnsupportedLowMemory
) : IllegalStateException("Device does not have enough RAM for local chat")

fun ChatDeviceCapability.isChatSupported(): Boolean =
    this !is ChatDeviceCapability.UnsupportedLowMemory

fun ChatDeviceCapability.requireChatSupported() {
    if (this is ChatDeviceCapability.UnsupportedLowMemory) {
        throw UnsupportedDeviceMemoryException(this)
    }
}
