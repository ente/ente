package io.ente.locker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File

object FileOpener {
    fun open(activity: Activity, filePath: String): Map<String, String> {
        val file = File(filePath)
        if (!file.exists()) {
            return mapOf(
                "resultType" to "fileNotFound",
                "message" to "File does not exist"
            )
        }

        val extension = file.extension.lowercase()
        val mimeType = if (extension.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
        } else {
            "*/*"
        }

        val uri = try {
            FileProvider.getUriForFile(activity, "${activity.packageName}.fileProvider", file)
        } catch (e: Exception) {
            return mapOf(
                "resultType" to "error",
                "message" to (e.message ?: "Failed to generate file URI")
            )
        }

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri(file.name, uri)
        }

        val chooser = Intent.createChooser(viewIntent, null)
        return try {
            activity.startActivity(chooser)
            mapOf("resultType" to "done", "message" to "done")
        } catch (_: ActivityNotFoundException) {
            mapOf(
                "resultType" to "noAppToOpen",
                "message" to "No application found to open this file"
            )
        } catch (e: Exception) {
            mapOf(
                "resultType" to "error",
                "message" to (e.message ?: "Failed to open file")
            )
        }
    }
}
