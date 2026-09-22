package io.ente.locker

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import com.kasem.receive_sharing_intent.FileDirectory
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.File
import java.nio.file.Files

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private var clearedOldShares = false
        private const val sharePrefix = "locker_share_"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (!clearedOldShares) {
            clearedOldShares = true
            val oldShares = cacheDir.listFiles()?.filter {
                it.isDirectory && it.name.startsWith(sharePrefix)
            }.orEmpty()
            Thread { oldShares.forEach { it.deleteRecursively() } }.start()
        }
        prepareSharedFiles(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        prepareSharedFiles(intent)
        super.onNewIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun prepareSharedFiles(intent: Intent) {
        val uris = when (intent.action) {
            Intent.ACTION_SEND -> listOf(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return)
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return
            else -> return
        }
        val prepared = uris.map { uri ->
            var directory: File? = null
            try {
                val path = FileDirectory.getAbsolutePath(this, uri)
                    ?: return@map Uri.EMPTY
                val source = File(path)
                if (uri.scheme != "content" || source.parentFile != cacheDir) {
                    return@map Uri.fromFile(source)
                }

                // Move this plugin copy before the next URI can overwrite its basename.
                directory = Files.createTempDirectory(cacheDir.toPath(), sharePrefix).toFile()
                val target = File(directory, source.name)
                Files.move(source.toPath(), target.toPath())
                Uri.fromFile(target)
            } catch (e: Exception) {
                directory?.deleteRecursively()
                Log.w("LockerSharing", "Unable to prepare shared document", e)
                Uri.EMPTY
            }
        }
        if (intent.action == Intent.ACTION_SEND) {
            intent.putExtra(Intent.EXTRA_STREAM, prepared.single())
            // Prevent thumbnail extraction when a shared video could not be read.
            if (prepared.single() == Uri.EMPTY) intent.type = "application/octet-stream"
            return
        }
        intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(prepared))
        intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.let { types ->
            intent.putExtra(Intent.EXTRA_MIME_TYPES, prepared.mapIndexed { index, uri ->
                if (uri == Uri.EMPTY) null else types.getOrNull(index)
            }.toTypedArray())
        }
    }
}
