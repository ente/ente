package io.ente.background

import android.app.Application
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BackgroundManagerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    internal var observesOutcomes = false
        private set

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel =
            MethodChannel(binding.binaryMessenger, CONTROL_CHANNEL).also {
                it.setMethodCallHandler(this)
            }
        BackgroundRuntime.attach(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        observesOutcomes = false
        BackgroundRuntime.detach(this)
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                observesOutcomes = true
                BackgroundRuntime.configure(call.arguments as? Map<*, *>, result)
            }
            "stopActiveRun" -> {
                BackgroundRuntime.requestStop(result)
            }
            "scheduledTasks" -> BackgroundRuntime.scheduledTasks(result)
            else -> result.notImplemented()
        }
    }

    internal fun report(event: Map<String, Any?>, fallback: () -> Unit) {
        val current = channel
        if (!observesOutcomes || current == null) {
            fallback()
            return
        }
        current.invokeMethod(
            "outcome",
            event,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result != true) fallback()
                }

                override fun error(code: String, message: String?, details: Any?) = fallback()

                override fun notImplemented() = fallback()
            },
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        BackgroundRuntime.foreground()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        BackgroundRuntime.foreground()
    }

    override fun onDetachedFromActivityForConfigChanges() = Unit

    override fun onDetachedFromActivity() = Unit

    companion object {
        internal const val CONTROL_CHANNEL = "io.ente.background/control"

        fun install(application: Application, isEnabled: () -> Boolean) {
            BackgroundRuntime.install(application, isEnabled)
        }

        fun onForeground() {
            BackgroundRuntime.foreground()
        }
    }
}
