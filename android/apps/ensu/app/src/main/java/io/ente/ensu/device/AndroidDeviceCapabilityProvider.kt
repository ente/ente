package io.ente.ensu.device

import android.app.ActivityManager
import android.content.Context

class AndroidDeviceCapabilityProvider(context: Context) {
    private val appContext = context.applicationContext

    fun isLowMemory(): Boolean {
        val manager = appContext.getSystemService(ActivityManager::class.java) ?: return false
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return info.lowMemory
    }

    fun modelMemoryHeadroom(
        optionalWork: Boolean = true,
        optionalReserveCapBytes: Long? = null,
    ): ULong? {
        val manager = appContext.getSystemService(ActivityManager::class.java) ?: return null
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return when {
            info.lowMemory -> 0uL
            info.totalMem <= 0 || info.availMem < 0 -> null
            else ->
                modelMemoryHeadroomBytes(
                    info.totalMem,
                    info.availMem,
                    info.threshold,
                    optionalWork,
                    optionalReserveCapBytes,
                )
        }
    }

    fun chatCapability(): ChatDeviceCapability {
        val activityManager =
            appContext.getSystemService(ActivityManager::class.java)
                ?: return ChatDeviceCapability.Unknown
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val totalMemoryBytes = memoryInfo.totalMem
        return if (totalMemoryBytes < CHAT_MIN_RAM_BYTES) {
            ChatDeviceCapability.UnsupportedLowMemory(totalMemoryBytes)
        } else {
            ChatDeviceCapability.Supported(totalMemoryBytes)
        }
    }
}

internal fun modelMemoryHeadroomBytes(
    totalBytes: Long,
    availableBytes: Long,
    lowMemoryThreshold: Long,
    optionalWork: Boolean = true,
    optionalReserveCapBytes: Long? = null,
): ULong {
    val systemReserve =
        maxOf(
            lowMemoryThreshold,
            if (optionalWork) minOf(totalBytes / 10, optionalReserveCapBytes ?: Long.MAX_VALUE)
            else 0,
        )
    return (availableBytes - systemReserve).coerceAtLeast(0).toULong()
}
