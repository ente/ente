package io.ente.photos.platform

import io.ente.photos.platform.flutter.DeviceHealthChannelAdapter
import io.ente.photos.platform.flutter.ProcessLockChannelAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin

class PhotosPlatformPlugin : FlutterPlugin {
    private val deviceHealthAdapter = DeviceHealthChannelAdapter()
    private val processLockAdapter = ProcessLockChannelAdapter()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        deviceHealthAdapter.attach(binding)
        processLockAdapter.attach(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        deviceHealthAdapter.detach()
        processLockAdapter.detach()
    }
}
