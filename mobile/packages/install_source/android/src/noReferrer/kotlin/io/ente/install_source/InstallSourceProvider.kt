package io.ente.install_source

import android.content.Context
import io.flutter.plugin.common.MethodChannel

class InstallSourceProvider(context: Context) {
    private val store = InstallSourceEventStore(context)

    fun hasInstallSource(result: MethodChannel.Result) {
        store.saveSource(InstallSource(emptyMap()))
        result.success(false)
    }

    fun autoAttributeSource(isSignUp: Boolean, result: MethodChannel.Result) {
        store.saveSource(InstallSource(emptyMap()))
        store.autoAttributeSource(isSignUp)
        result.success(null)
    }

    fun getPendingEvents(result: MethodChannel.Result) {
        result.success(emptyList<String>())
    }

    fun markEventSent(event: String?, result: MethodChannel.Result) {
        result.success(null)
    }
}
