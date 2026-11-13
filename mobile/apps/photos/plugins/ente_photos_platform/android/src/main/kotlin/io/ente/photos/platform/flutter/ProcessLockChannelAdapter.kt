package io.ente.photos.platform.flutter

import io.ente.photos.platform.processlock.ProcessLockRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal class ProcessLockChannelAdapter : MethodChannel.MethodCallHandler {
    private lateinit var methodChannel: MethodChannel
    private val instanceId = UUID.randomUUID().toString()

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "processLock.tryAcquire" -> {
                val name = call.argument<String>("name")
                val origin = call.argument<String>("origin")
                val operation = call.argument<String>("operation")
                if (name.isNullOrEmpty() || origin.isNullOrEmpty() || operation.isNullOrEmpty()) {
                    result.error(
                        "invalidArguments",
                        "name, origin and operation are required",
                        null,
                    )
                } else {
                    result.success(
                        ProcessLockRegistry.tryAcquire(name, instanceId, origin, operation),
                    )
                }
            }
            "processLock.release" -> {
                val name = call.argument<String>("name")
                if (name.isNullOrEmpty()) {
                    result.error("invalidArguments", "name is required", null)
                } else {
                    result.success(ProcessLockRegistry.release(name, instanceId))
                }
            }
            "processLock.state" -> {
                val name = call.argument<String>("name")
                if (name.isNullOrEmpty()) {
                    result.error("invalidArguments", "name is required", null)
                } else {
                    result.success(ProcessLockRegistry.state(name))
                }
            }
            else -> result.notImplemented()
        }
    }

    fun detach() {
        ProcessLockRegistry.releaseAllForInstance(instanceId)
        methodChannel.setMethodCallHandler(null)
    }

    private companion object {
        const val METHOD_CHANNEL = "io.ente.photos.platform/process_lock"
    }
}
