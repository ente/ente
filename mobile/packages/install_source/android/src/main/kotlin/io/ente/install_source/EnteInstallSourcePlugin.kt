package io.ente.install_source

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EnteInstallSourcePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var provider: InstallSourceProvider

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        provider = InstallSourceProvider(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasInstallSource" -> provider.hasInstallSource(result)
            "autoAttributeSource" -> provider.autoAttributeSource(
                call.argument<Boolean>("isSignUp") == true,
                result,
            )

            "getPendingEvents" -> provider.getPendingEvents(result)
            "markEventSent" -> provider.markEventSent(call.argument("event"), result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL = "io.ente.install_source/install_source"
    }
}
