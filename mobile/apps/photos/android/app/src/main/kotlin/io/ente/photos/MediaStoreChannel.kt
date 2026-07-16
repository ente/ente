package io.ente.photos

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class MediaStoreChannel(private val activity: MainActivity) {
    companion object {
        private const val CHANNEL = "io.ente.photos/media_store"
        private const val POOL_SIZE = 8
        private val threadPool: ThreadPoolExecutor = ThreadPoolExecutor(
            POOL_SIZE,
            Int.MAX_VALUE,
            1,
            TimeUnit.MINUTES,
            LinkedBlockingQueue()
        )

        fun runOnBackground(runnable: () -> Unit) {
            threadPool.execute(runnable)
        }
    }

    private var pendingResult: MethodChannel.Result? = null
    private val mediaRequestLauncher = activity.registerForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult()
    ) { activityResult ->
        val result = pendingResult ?: return@registerForActivityResult
        pendingResult = null
        if (activityResult.resultCode == Activity.RESULT_OK) {
            result.success(null)
        } else {
            result.error("media_request_denied", "Media request was denied", null)
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canManageMedia" -> result.success(canManageMedia())
            "openManageMediaSettings" -> {
                openManageMediaSettings()
                result.success(null)
            }
            "restoreTrashedFiles" -> restoreTrashedFiles(call, result)
            "permanentlyDeleteTrashedFiles" -> permanentlyDeleteTrashedFiles(call, result)
            else -> result.notImplemented()
        }
    }

    private fun canManageMedia(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && MediaStore.canManageMedia(activity)
    }

    private fun openManageMediaSettings() {
        val intent = Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA).apply {
            data = Uri.parse("package:${activity.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    private fun restoreTrashedFiles(call: MethodCall, result: MethodChannel.Result) {
        startMediaRequest(call, result) { uris ->
            MediaStore.createTrashRequest(activity.contentResolver, uris, false)
        }
    }

    private fun permanentlyDeleteTrashedFiles(call: MethodCall, result: MethodChannel.Result) {
        startMediaRequest(call, result) { uris ->
            MediaStore.createDeleteRequest(activity.contentResolver, uris)
        }
    }

    private fun startMediaRequest(
        call: MethodCall,
        result: MethodChannel.Result,
        createRequest: (List<Uri>) -> android.app.PendingIntent
    ) {
        if (pendingResult != null) {
            result.error("request_in_progress", "Another media request is in progress", null)
            return
        }

        val uris = getUris(call)
        val request = createRequest(uris)
        mediaRequestLauncher.launch(
            IntentSenderRequest.Builder(request.intentSender).build()
        )
        pendingResult = result
    }

    private fun getUris(call: MethodCall): List<Uri> {
        val uris = call.argument<List<String>>("uris")
            ?: throw IllegalArgumentException("Missing uris")
        return uris.map(Uri::parse)
    }
}
