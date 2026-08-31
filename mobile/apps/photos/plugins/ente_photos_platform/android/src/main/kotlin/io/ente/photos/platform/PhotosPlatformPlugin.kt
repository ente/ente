package io.ente.photos.platform

import io.ente.photos.platform.flutter.CountryNamesChannelAdapter
import io.ente.photos.platform.flutter.DeviceHealthChannelAdapter
import io.ente.photos.platform.flutter.DeviceTrashChannelAdapter
import io.ente.photos.platform.flutter.ProcessLockChannelAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin

class PhotosPlatformPlugin : FlutterPlugin {
    private val countryNamesAdapter = CountryNamesChannelAdapter()
    private val deviceHealthAdapter = DeviceHealthChannelAdapter()
    private val deviceTrashAdapter = DeviceTrashChannelAdapter()
    private val processLockAdapter = ProcessLockChannelAdapter()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.attach(binding)
        deviceHealthAdapter.attach(binding)
        deviceTrashAdapter.attach(binding)
        processLockAdapter.attach(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.detach()
        deviceHealthAdapter.detach()
        deviceTrashAdapter.detach()
        processLockAdapter.detach()
    }
}
