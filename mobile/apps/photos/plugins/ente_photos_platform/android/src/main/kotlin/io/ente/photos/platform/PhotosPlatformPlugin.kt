package io.ente.photos.platform

import io.ente.photos.platform.flutter.CountryNamesChannelAdapter
import io.ente.photos.platform.flutter.DeviceFolderTransferChannelAdapter
import io.ente.photos.platform.flutter.DeviceHealthChannelAdapter
import io.ente.photos.platform.flutter.DeviceTrashChannelAdapter
import io.ente.photos.platform.flutter.ProcessLockChannelAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

class PhotosPlatformPlugin : FlutterPlugin, ActivityAware {
    private val countryNamesAdapter = CountryNamesChannelAdapter()
    private val deviceFolderTransferAdapter = DeviceFolderTransferChannelAdapter()
    private val deviceHealthAdapter = DeviceHealthChannelAdapter()
    private val deviceTrashAdapter = DeviceTrashChannelAdapter()
    private val processLockAdapter = ProcessLockChannelAdapter()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.attach(binding)
        deviceFolderTransferAdapter.attach(binding)
        deviceHealthAdapter.attach(binding)
        deviceTrashAdapter.attach(binding)
        processLockAdapter.attach(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.detach()
        deviceFolderTransferAdapter.detach()
        deviceHealthAdapter.detach()
        deviceTrashAdapter.detach()
        processLockAdapter.detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        deviceFolderTransferAdapter.attachActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        deviceFolderTransferAdapter.detachActivity(cancelPendingConsent = false)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        deviceFolderTransferAdapter.attachActivity(binding)
    }

    override fun onDetachedFromActivity() {
        deviceFolderTransferAdapter.detachActivity(cancelPendingConsent = true)
    }
}
