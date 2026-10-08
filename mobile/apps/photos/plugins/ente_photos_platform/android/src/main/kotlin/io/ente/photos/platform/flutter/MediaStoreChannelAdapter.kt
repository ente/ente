package io.ente.photos.platform.flutter

import android.content.ContentResolver
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

internal class MediaStoreChannelAdapter : MethodChannel.MethodCallHandler {
    private lateinit var contentResolver: ContentResolver
    private lateinit var methodChannel: MethodChannel

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        contentResolver = binding.applicationContext.contentResolver
        methodChannel =
            MethodChannel(
                binding.binaryMessenger,
                METHOD_CHANNEL,
                StandardMethodCodec.INSTANCE,
                binding.binaryMessenger.makeBackgroundTaskQueue(),
            )
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "mediaStore.assetExists") {
            result.notImplemented()
            return
        }
        try {
            val id = requireNotNull(call.argument<String>("id"))
            val cursor =
                contentResolver.query(
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

    fun detach() {
        methodChannel.setMethodCallHandler(null)
    }

    private companion object {
        const val METHOD_CHANNEL = "io.ente.photos.platform/media_store"
    }
}
