package io.ente.photos.platform

import io.ente.photos.platform.flutter.PhotosPlatformChannelRouter
import io.ente.photos.platform.flutter.ProcessLockChannelAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin

class PhotosPlatformPlugin : FlutterPlugin {
    private val channelRouter = PhotosPlatformChannelRouter()
    private val processLockAdapter = ProcessLockChannelAdapter()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channelRouter.attach(binding)
        processLockAdapter.attach(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channelRouter.detach()
        processLockAdapter.detach()
    }
}
