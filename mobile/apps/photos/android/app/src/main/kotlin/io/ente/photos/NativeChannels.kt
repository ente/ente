package io.ente.photos

import android.os.Build
import android.provider.MediaStore
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeChannels {
    fun register(context: Context, flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MediaStoreChannel(context.applicationContext).register(messenger)
    }
}

private class MediaStoreChannel(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isMediaManagementSupported" -> result.success(isMediaManagementSupported())
            "canManageMedia" -> result.success(canManageMedia())
            "openManageMediaSettings" -> {
                openManageMediaSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
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

    private companion object {
        const val CHANNEL = "io.ente.photos/media_store"
    }
}
