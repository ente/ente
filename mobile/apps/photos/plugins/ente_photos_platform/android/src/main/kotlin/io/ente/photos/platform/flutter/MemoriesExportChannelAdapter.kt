package io.ente.photos.platform.flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

internal class MemoriesExportChannelAdapter {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "io.ente.photos.platform/memories_export"
        )
        channel?.setMethodCallHandler({ call, result ->
            if (call.method == "memoriesExport.export") {
                result.error("not_implemented", "Memories export is not implemented", null)
            } else if (call.method == "memoriesExport.cancel") {
                result.success(null)
            } else {
                result.notImplemented()
            }
        })
    }

    fun reportProgress(progress: Double) {
        mainHandler.post({
            channel?.invokeMethod("memoriesExport.progress", progress)
        })
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
