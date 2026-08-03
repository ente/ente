package io.ente.photos

import android.content.ContentResolver
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.fluttercandies.photo_manager.core.PhotoManagerPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeChannel {
    private const val CHANNEL_NAME = "ente.io/photos/native"
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, contentResolver: ContentResolver) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            handle(call, result, contentResolver)
        }
    }

    private fun handle(
        call: MethodCall,
        result: MethodChannel.Result,
        contentResolver: ContentResolver,
    ) {
        when (call.method) {
            "getTrash" -> PhotoManagerPlugin.runOnBackground {
                try {
                    val files = getTrash(contentResolver)
                    mainHandler.post { result.success(files) }
                } catch (error: Exception) {
                    mainHandler.post {
                        result.error(
                            "media_store_query_failed",
                            error.message,
                            null,
                        )
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun getTrash(contentResolver: ContentResolver): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()

        val files = mutableListOf<Map<String, Any>>()
        val uri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val queryArgs = Bundle().apply {
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
                    "(${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, " +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})",
            )
            putString(
                ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                "${MediaStore.Files.FileColumns.DATE_EXPIRES} DESC",
            )
        }

        contentResolver.query(
            uri,
            arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.DATE_EXPIRES,
                MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME,
            ),
            queryArgs,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                files.add(
                    mapOf(
                        "localID" to cursor.getLong(0),
                        "deleteBy" to cursor.getLong(1) * 1_000_000,
                        "deviceFolder" to (cursor.getString(2) ?: "Unknown Folder"),
                    ),
                )
            }
        }
        return files
    }
}
