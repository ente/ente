package io.ente.photos.platform.devicetrash

import android.content.ContentResolver
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.util.concurrent.Executors

internal data class DeviceTrashFile(
    val localID: Long,
    val deleteBy: Long,
    val deviceFolder: String,
)

internal class DeviceTrashService(context: Context) {
    private val contentResolver = context.applicationContext.contentResolver
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var isClosed = false

    fun getFiles(
        onSuccess: (List<DeviceTrashFile>) -> Unit,
        onFailure: (Exception) -> Unit,
    ) {
        executor.execute {
            try {
                val files = queryFiles()
                mainHandler.post {
                    if (!isClosed) onSuccess(files)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    if (!isClosed) onFailure(error)
                }
            }
        }
    }

    fun close() {
        isClosed = true
        executor.shutdownNow()
        mainHandler.removeCallbacksAndMessages(null)
    }

    private fun queryFiles(): List<DeviceTrashFile> {
        val projection =
            arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.MediaColumns.DATE_EXPIRES,
                MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
            )
        val queryArgs =
            Bundle().apply {
                putString(
                    ContentResolver.QUERY_ARG_SQL_SELECTION,
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
                        "(${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, " +
                        "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})",
                )
                putString(
                    ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                    "${MediaStore.MediaColumns.DATE_EXPIRES} DESC",
                )
                putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            }
        val files = mutableListOf<DeviceTrashFile>()
        contentResolver.query(
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
            projection,
            queryArgs,
            null,
        )?.use { cursor ->
            val localIDColumn = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val deleteByColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_EXPIRES)
            val deviceFolderColumn =
                cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                files +=
                    DeviceTrashFile(
                        localID = cursor.getLong(localIDColumn),
                        deleteBy =
                            cursor.getLong(deleteByColumn) *
                                MICROSECONDS_PER_SECOND,
                        deviceFolder =
                            cursor.getString(deviceFolderColumn)
                                ?.takeUnless(String::isBlank)
                                ?: "Unknown Folder",
                    )
            }
        }
        return files
    }

    private companion object {
        const val MICROSECONDS_PER_SECOND = 1_000_000L
    }
}
