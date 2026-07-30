package io.ente.ensu.device

import android.app.ActivityManager
import android.content.Context
import io.ente.ensu.device.CHAT_MIN_RAM_BYTES
import io.ente.ensu.device.ChatDeviceCapability

class AndroidDeviceCapabilityProvider(context: Context) {
    private val appContext = context.applicationContext

    fun chatCapability(): ChatDeviceCapability {
        val activityManager = appContext.getSystemService(ActivityManager::class.java)
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
