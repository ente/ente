package io.ente.photos.platform.flutter

import android.os.Build
import io.ente.photos.platform.devicetrash.DeviceTrashFile
import io.ente.photos.platform.devicetrash.DeviceTrashService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class DeviceTrashChannelAdapter : MethodChannel.MethodCallHandler {
    private lateinit var service: DeviceTrashService

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        service = DeviceTrashService(binding.applicationContext)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) =
        when (call.method) {
            "deviceTrash.getFiles" ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    result.error("device_trash_unsupported", null, null)
                } else {
                    service.getFiles(
                        onSuccess = { files -> result.success(files.map { it.toChannelMap() }) },
                        onFailure = { error ->
                            result.error("device_trash_query_failed", error.message, null)
                        },
                    )
                }

            else -> result.notImplemented()
        }

    fun detach() {
        service.close()
    }

    private fun DeviceTrashFile.toChannelMap(): Map<String, Any> =
        mapOf(
            "localID" to localID,
            "deleteBy" to deleteBy,
            "deviceFolder" to deviceFolder,
        )
}
