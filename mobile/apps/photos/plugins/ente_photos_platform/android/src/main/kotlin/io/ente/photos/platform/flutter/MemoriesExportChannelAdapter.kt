package io.ente.photos.platform.flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

internal class MemoriesExportChannelAdapter {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var activeExportCancelFlag: AtomicBoolean? = null

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            binding.binaryMessenger,
            "io.ente.photos.platform/memories_export"
        )
        channel?.setMethodCallHandler({ call, result ->
            if (call.method == "memoriesExport.export") {
                val cancelFlag = AtomicBoolean(false)
                activeExportCancelFlag = cancelFlag
                mainHandler.post({
                    if (cancelFlag.get()) {
                        result.success(null)
                    } else {
                        result.error("not_implemented", "Memories export is not implemented", null)
                    }
                    activeExportCancelFlag = null
                })
            } else if (call.method == "memoriesExport.cancel") {
                activeExportCancelFlag?.set(true)
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
        activeExportCancelFlag?.set(true)
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
