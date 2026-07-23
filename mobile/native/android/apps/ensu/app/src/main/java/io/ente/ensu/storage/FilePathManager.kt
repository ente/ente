package io.ente.ensu.storage

import android.content.Context
import java.io.File

class FilePathManager(context: Context) {
    private val appDataDir: File = ensureDir(context.filesDir)
    val attachmentsDir: File = ensureDir(File(appDataDir, "attachments"))
    val mainDbFile: File = File(appDataDir, "llmchat.db")
    val hasChatData: Boolean
        get() = mainDbFile.exists() || (attachmentsDir.list()?.isNotEmpty() ?: true)

    private fun ensureDir(dir: File): File {
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }
}
