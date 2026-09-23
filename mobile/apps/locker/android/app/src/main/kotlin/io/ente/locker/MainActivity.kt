package io.ente.locker

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import com.kasem.receive_sharing_intent.FileDirectory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private var clearedOldShares = false
        private const val sharePrefix = "locker_share_"
        private const val channelName = "io.ente.locker/shared_files"
        private val shareExecutor = Executors.newSingleThreadExecutor()
        private val pendingShares = mutableListOf<List<String>>()
        private var sharedFilesChannel: MethodChannel? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (!clearedOldShares) {
            clearedOldShares = true
            val oldShares = cacheDir.listFiles()?.filter {
                it.isDirectory && it.name.startsWith(sharePrefix)
            }.orEmpty()
            Thread { oldShares.forEach { it.deleteRecursively() } }.start()
        }
        val sharedIntent = intent.takeIf(::isFileShare)?.let(::Intent)
        // The sharing plugin must not copy the original streams during attachment.
        if (sharedIntent != null) setIntent(Intent(Intent.ACTION_MAIN))
        super.onCreate(savedInstanceState)
        sharedIntent?.let(::enqueueSharedFiles)
    }

    override fun onNewIntent(intent: Intent) {
        if (isFileShare(intent)) {
            enqueueSharedFiles(Intent(intent))
            return
        }
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedFilesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "takeNextShare") {
                    result.success(pendingShares.removeFirstOrNull())
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sharedFilesChannel?.setMethodCallHandler(null)
        sharedFilesChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Suppress("DEPRECATION")
    private fun isFileShare(intent: Intent): Boolean = when (intent.action) {
        Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) != null
        Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) != null
        else -> false
    }

    private fun enqueueSharedFiles(intent: Intent) {
        shareExecutor.execute {
            val files = prepareSharedFiles(intent)
            runOnUiThread {
                pendingShares.add(files)
                sharedFilesChannel?.invokeMethod("sharesReady", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun prepareSharedFiles(intent: Intent): List<String> {
        val uris = when (intent.action) {
            Intent.ACTION_SEND -> listOf(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return emptyList())
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return emptyList()
            else -> return emptyList()
        }
        return uris.map { uri ->
            var directory: File? = null
            try {
                val path = FileDirectory.getAbsolutePath(this, uri)
                    ?: return@map ""
                val source = File(path)
                if (uri.scheme != "content" || source.parentFile != cacheDir) {
                    return@map source.path
                }

                directory = Files.createTempDirectory(cacheDir.toPath(), sharePrefix).toFile()
                val target = File(directory, source.name)
                Files.move(source.toPath(), target.toPath())
                target.path
            } catch (e: Exception) {
                directory?.deleteRecursively()
                Log.w("LockerSharing", "Unable to prepare shared document", e)
                ""
            }
        }
    }
}
