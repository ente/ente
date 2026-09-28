package io.ente.locker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
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
        private var shareGeneration = 0
        private var sessionGeneration = 0
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (!clearedOldShares) {
            clearedOldShares = true
            val oldShares = cacheDir.listFiles()?.filter {
                it.isDirectory && it.name.startsWith(sharePrefix)
            }.orEmpty()
            Thread { oldShares.forEach { it.deleteRecursively() } }.start()
        }
        val uris = sharedUris(intent)
        // The sharing plugin must not copy the original streams during attachment.
        if (uris != null) setIntent(Intent(Intent.ACTION_MAIN))
        super.onCreate(savedInstanceState)
        uris?.let(::enqueueSharedFiles)
    }

    override fun onNewIntent(intent: Intent) {
        val uris = sharedUris(intent)
        if (uris != null) {
            enqueueSharedFiles(uris)
            return
        }
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedFilesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "takeNextShare" && call.method != "clearPendingShares") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val generation = call.arguments as Int
                // Retry invalidation on reads if the logout channel call failed.
                if (generation != sessionGeneration) {
                    sessionGeneration = generation
                    shareGeneration++
                    val discarded = pendingShares.flatten()
                    pendingShares.clear()
                    shareExecutor.execute { deletePreparedFiles(discarded) }
                }
                result.success(if (call.method == "takeNextShare") pendingShares.removeFirstOrNull() else null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sharedFilesChannel?.setMethodCallHandler(null)
        sharedFilesChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun sharedUris(intent: Intent): List<Uri>? {
        if (intent.action != Intent.ACTION_SEND_MULTIPLE) return null
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }

    private fun enqueueSharedFiles(uris: List<Uri>) {
        val generation = shareGeneration
        shareExecutor.execute {
            val files = prepareSharedFiles(uris)
            runOnUiThread {
                if (generation != shareGeneration) {
                    shareExecutor.execute { deletePreparedFiles(files) }
                    return@runOnUiThread
                }
                pendingShares.add(files)
                sharedFilesChannel?.invokeMethod("sharesReady", null)
            }
        }
    }

    private fun deletePreparedFiles(files: Iterable<String>) {
        files.map { File(it).parentFile }.filter {
            it?.parentFile == cacheDir && it.name.startsWith(sharePrefix)
        }.forEach { it.deleteRecursively() }
    }

    private fun prepareSharedFiles(uris: List<Uri>): List<String> {
        return uris.map { uri ->
            var directory: File? = null
            try {
                val name = runCatching {
                    if (uri.scheme == "file") File(uri.path!!).name else {
                        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                            if (it.moveToFirst()) it.getString(0) else null
                        }
                    }
                }.getOrNull()
                val safeName = name?.let { File(it).name }?.takeIf { it.isNotBlank() && it != "." && it != ".." }
                    ?: run {
                        val extension = runCatching {
                            MimeTypeMap.getSingleton().getExtensionFromMimeType(contentResolver.getType(uri))
                        }.getOrNull()
                        "Shared file" + (extension?.let { ".$it" } ?: "")
                    }
                directory = Files.createTempDirectory(cacheDir.toPath(), sharePrefix).toFile()
                val target = File(directory, safeName)
                (contentResolver.openInputStream(uri) ?: error("Shared document could not be opened")).use { input ->
                    target.outputStream().use { input.copyTo(it) }
                }
                target.path
            } catch (e: Exception) {
                directory?.deleteRecursively()
                Log.w("LockerSharing", "Unable to prepare shared document", e)
                ""
            }
        }
    }
}
