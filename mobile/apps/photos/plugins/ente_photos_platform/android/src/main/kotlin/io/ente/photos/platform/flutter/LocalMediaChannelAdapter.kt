package io.ente.photos.platform.flutter

import android.content.ContentResolver
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

internal class LocalMediaChannelAdapter : MethodChannel.MethodCallHandler {
    private lateinit var contentResolver: ContentResolver
    private lateinit var methodChannel: MethodChannel

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        contentResolver = binding.applicationContext.contentResolver
        methodChannel =
            MethodChannel(
                binding.binaryMessenger,
                "io.ente.photos.platform/local_media",
                StandardMethodCodec.INSTANCE,
                binding.binaryMessenger.makeBackgroundTaskQueue(),
            )
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method == "localMedia.missingHeicRotation") {
            try {
                result.success(missingHeicRotation(requireNotNull(call.argument<String>("path"))))
            } catch (error: Exception) {
                result.error("heic_rotation_failed", error.message, null)
            }
            return
        }
        if (call.method != "localMedia.assetExists") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(null)
            return
        }
        try {
            val localID = requireNotNull(call.argument<String>("localID")?.toLongOrNull())
            require(localID >= 0)
            val uri = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID)
            val selection = "${MediaStore.Files.FileColumns._ID} = ?"
            val selectionArgs = arrayOf(localID.toString())
            val queryArgs =
                Bundle().apply {
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                    putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
                    putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
                    putBoolean(MediaStore.QUERY_ARG_INCLUDE_RECENTLY_UNMOUNTED_VOLUMES, true)
                }
            val cursor = contentResolver.query(uri, projection, queryArgs, null)
            checkNotNull(cursor) { "MediaStore query returned no cursor" }
            val exists = cursor.use { it.moveToFirst() }
            result.success(exists)
        } catch (error: Exception) {
            result.error("local_media_query_failed", error.message, null)
        }
    }

    private fun missingHeicRotation(path: String): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val retriever = MediaMetadataRetriever()
        val rotation = try {
            retriever.setDataSource(path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_IMAGE_ROTATION)?.toIntOrNull()
        } finally {
            retriever.release()
        }
        if (rotation != 180) return null
        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
        return rotation.takeIf { orientation <= ExifInterface.ORIENTATION_NORMAL }
    }

    fun detach() {
        methodChannel.setMethodCallHandler(null)
    }
}
