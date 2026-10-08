package io.ente.photos.platform

import android.provider.MediaStore
import io.ente.photos.platform.flutter.CountryNamesChannelAdapter
import io.ente.photos.platform.flutter.DeviceHealthChannelAdapter
import io.ente.photos.platform.flutter.DeviceTrashChannelAdapter
import io.ente.photos.platform.flutter.ProcessLockChannelAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class PhotosPlatformPlugin : FlutterPlugin {
    private val countryNamesAdapter = CountryNamesChannelAdapter()
    private val deviceHealthAdapter = DeviceHealthChannelAdapter()
    private val deviceTrashAdapter = DeviceTrashChannelAdapter()
    private val processLockAdapter = ProcessLockChannelAdapter()
    private var mediaStoreChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.attach(binding)
        deviceHealthAdapter.attach(binding)
        deviceTrashAdapter.attach(binding)
        processLockAdapter.attach(binding)
        mediaStoreChannel =
            MethodChannel(
                    binding.binaryMessenger,
                    "io.ente.photos.platform/media_store",
                    StandardMethodCodec.INSTANCE,
                    binding.binaryMessenger.makeBackgroundTaskQueue(),
                )
                .apply {
                    setMethodCallHandler { call, result ->
                        if (call.method != "mediaStore.assetExists") {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                        try {
                            val id = requireNotNull(call.argument<String>("id"))
                            val cursor =
                                binding.applicationContext.contentResolver.query(
                                    MediaStore.Files.getContentUri("external"),
                                    arrayOf(MediaStore.Files.FileColumns._ID),
                                    "${MediaStore.Files.FileColumns._ID} = ?",
                                    arrayOf(id),
                                    null,
                                ) ?: error("MediaStore query returned no cursor")
                            val exists = cursor.use { it.moveToFirst() }
                            result.success(exists)
                        } catch (error: Exception) {
                            result.error("media_store_query_failed", error.message, null)
                        }
                    }
                }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        countryNamesAdapter.detach()
        deviceHealthAdapter.detach()
        deviceTrashAdapter.detach()
        processLockAdapter.detach()
        mediaStoreChannel?.setMethodCallHandler(null)
        mediaStoreChannel = null
    }
}
