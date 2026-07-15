package io.ente.photos

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import androidx.annotation.ChecksSdkIntAtLeast
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

object NativeChannels {
    private var mediaStoreChannel: MediaStoreChannel? = null

    fun register(activity: Activity, flutterEngine: FlutterEngine) {
        mediaStoreChannel?.close()
        mediaStoreChannel = MediaStoreChannel(activity).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        mediaStoreChannel?.onActivityResult(requestCode, resultCode)
    }

    fun unregister(activity: Activity) {
        if (mediaStoreChannel?.activity === activity) {
            mediaStoreChannel?.close()
            mediaStoreChannel = null
        }
    }
}

private class MediaStoreChannel(val activity: Activity) {
    private val context = activity.applicationContext
    private val contentResolver = activity.contentResolver
    private val worker = ThreadPoolExecutor(
        POOL_SIZE,
        Int.MAX_VALUE,
        1,
        TimeUnit.MINUTES,
        LinkedBlockingQueue(),
    )
    private var channel: MethodChannel? = null
    private var pendingRequestResult: MethodChannel.Result? = null
    private var pendingRequestCode: Int? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(::handle)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isMediaManagementSupported" -> result.success(isMediaManagementSupported())
                "canManageMedia" -> result.success(canManageMedia())
                "openManageMediaSettings" -> {
                    openManageMediaSettings()
                    result.success(null)
                }
                "getTrashItems" -> if (checkTrashSupport(result)) {
                    runInBackground(result) { getTrashItems() }
                }
                "getTrashFileBytes" -> {
                    if (!checkTrashSupport(result)) return
                    val uri = call.argument<String>("uri")
                        ?: return result.error("bad_uri", "The trash item URI is missing.", null)
                    runInBackground(result) {
                        contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
                            ?: throw IllegalStateException("Could not open trash item $uri")
                    }
                }
                "restoreTrashItem", "deleteTrashItem" -> {
                    if (!checkTrashSupport(result)) return
                    val localID = call.argument<String>("localID")
                        ?: return result.error("bad_local_id", "The trash item ID is missing.", null)
                    val items = listOf(Uri.parse(localID))
                    val delete = call.method == "deleteTrashItem"
                    startRequest(
                        result,
                        if (delete) DELETE_REQUEST_CODE else RESTORE_REQUEST_CODE,
                        if (delete) MediaStore.createDeleteRequest(contentResolver, items)
                        else MediaStore.createTrashRequest(contentResolver, items, false),
                    )
                }

                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            sendError(result, error)
        }
    }

    @ChecksSdkIntAtLeast(api = Build.VERSION_CODES.R)
    private fun checkTrashSupport(result: MethodChannel.Result): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return true
        }
        result.error(
            "unsupported_android_version",
            "Android trash needs Android 11 or newer.",
            null,
        )
        return false
    }

    private fun runInBackground(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        worker.execute {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread { sendError(result, error) }
            }
        }
    }

    private fun sendError(result: MethodChannel.Result, error: Exception) {
        result.error(
            error.javaClass.simpleName,
            error.message,
            error.stackTraceToString(),
        )
    }

    private fun isMediaManagementSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    }

    private fun canManageMedia(): Boolean {
        return isMediaManagementSupported() && MediaStore.canManageMedia(context)
    }

    private fun openManageMediaSettings() {
        if (!isMediaManagementSupported()) {
            return
        }
        val intent = Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun getTrashItems(): List<Map<String, Any?>> {
        val collection = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.VOLUME_NAME,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DATE_EXPIRES,
        )
        val queryArgs = Bundle().apply {
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            putStringArray(
                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.MediaColumns.DATE_EXPIRES),
            )
            putInt(
                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                ContentResolver.QUERY_SORT_DIRECTION_ASCENDING,
            )
        }
        val items = mutableListOf<Map<String, Any?>>()

        contentResolver.query(collection, projection, queryArgs, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val volumeColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.VOLUME_NAME)
            val nameColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val folderColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val dateTakenColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val dateModifiedColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val dateExpiresColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_EXPIRES)

            while (cursor.moveToNext()) {
                val mimeType = cursor.getString(mimeColumn)
                if (mimeType?.startsWith("image/") != true) {
                    continue
                }
                val itemUri = ContentUris.withAppendedId(
                    MediaStore.Images.Media.getContentUri(cursor.getString(volumeColumn)),
                    cursor.getLong(idColumn),
                )
                val modificationTime = cursor.getLong(dateModifiedColumn) * MICROSECONDS_PER_SECOND
                val dateTaken = if (cursor.isNull(dateTakenColumn)) {
                    0
                } else {
                    cursor.getLong(dateTakenColumn) * MICROSECONDS_PER_MILLISECOND
                }
                val creationTime = dateTaken.takeIf { it > 0 } ?: modificationTime
                val deleteBy = if (cursor.isNull(dateExpiresColumn)) {
                    null
                } else {
                    cursor.getLong(dateExpiresColumn) * MICROSECONDS_PER_SECOND
                }
                items += mapOf(
                    "localID" to itemUri.toString(),
                    "title" to cursor.getString(nameColumn),
                    "deviceFolder" to cursor.getString(folderColumn),
                    "creationTime" to creationTime,
                    "modificationTime" to modificationTime,
                    "fileType" to IMAGE_FILE_TYPE,
                    "subType" to 0,
                    "duration" to 0,
                    "version" to -1,
                    "fileSize" to cursor.getLong(sizeColumn),
                    "deleteBy" to deleteBy,
                    "thumbnail" to loadThumbnail(itemUri),
                )
            }
        }
        return items
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun loadThumbnail(itemUri: Uri): ByteArray {
        val bitmap = contentResolver.loadThumbnail(
            itemUri,
            Size(THUMBNAIL_SIZE, THUMBNAIL_SIZE),
            null,
        )
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, THUMBNAIL_QUALITY, output)
            bitmap.recycle()
            output.toByteArray()
        }
    }

    private fun startRequest(
        result: MethodChannel.Result,
        requestCode: Int,
        request: PendingIntent,
    ) {
        if (pendingRequestResult != null) {
            result.error("trash_request_in_progress", "A trash request is already open.", null)
            return
        }

        try {
            pendingRequestResult = result
            pendingRequestCode = requestCode
            activity.startIntentSenderForResult(
                request.intentSender,
                requestCode,
                null,
                0,
                0,
                0,
            )
        } catch (error: Exception) {
            pendingRequestResult = null
            pendingRequestCode = null
            sendError(result, error)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != pendingRequestCode) {
            return
        }
        pendingRequestResult?.success(resultCode == Activity.RESULT_OK)
        pendingRequestResult = null
        pendingRequestCode = null
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingRequestResult?.error("activity_closed", "The app was closed.", null)
        pendingRequestResult = null
        pendingRequestCode = null
        worker.shutdownNow()
    }

    private companion object {
        const val CHANNEL = "io.ente.photos/media_store"
        const val DELETE_REQUEST_CODE = 7302
        const val IMAGE_FILE_TYPE = 0
        const val MICROSECONDS_PER_MILLISECOND = 1_000L
        const val MICROSECONDS_PER_SECOND = 1_000_000L
        const val POOL_SIZE = 8
        const val RESTORE_REQUEST_CODE = 7301
        const val THUMBNAIL_QUALITY = 50
        const val THUMBNAIL_SIZE = 256
    }
}
