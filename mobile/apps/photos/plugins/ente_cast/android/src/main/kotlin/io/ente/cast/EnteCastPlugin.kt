package io.ente.cast

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class EnteCastPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var lock: WifiManager.MulticastLock
    private var holderCount = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val wifiManager = binding.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        lock = wifiManager.createMulticastLock("ente_cast_discovery").apply {
            setReferenceCounted(false)
        }
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                if (holderCount == 0) {
                    lock.acquire()
                }
                holderCount++
                result.success(null)
            }
            "release" -> {
                if (holderCount > 0 && --holderCount == 0 && lock.isHeld) {
                    lock.release()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        holderCount = 0
        if (lock.isHeld) {
            lock.release()
        }
    }

    private companion object {
        const val CHANNEL = "io.ente.cast/multicast"
    }
}
