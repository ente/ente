package io.ente.photos.media_extension

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.*
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.*
import java.util.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.collections.HashMap

private const val MediaStorePendingItemErrorPrefix =
    "Only owner is able to interact with pending"

internal fun isMediaStorePendingItemError(message: String?): Boolean {
    return message?.contains(MediaStorePendingItemErrorPrefix, ignoreCase = true) == true
}

class MediaExtensionPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener, PluginRegistry.NewIntentListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val logTag = "EnteMediaExtension"

    enum class IntentAction {
        MAIN,
        PICK,
        EDIT,
        VIEW
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "media_extension")

        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "getIntentAction" -> {
                result.success(getIntentAction())
            }
            "setResult" -> {
                setResult(call, result)
            }
            "setResults" -> {
                setResults(call, result)
            }
            "cancelResult" -> {
                cancelResult(result)
            }
            "setAs" -> {
                setAs(call, result)
            }
            "edit" -> {
                edit(call, result)
            }
            "openWith" -> {
                openWith(call, result)
            }
            "readUriBytes" -> {
                readUriBytes(call, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getResolvedContent(
        contentUri: Uri,
        contentType: String,
        resolvedContent: HashMap<String, String>
    ) {
        val resolver = context.contentResolver
        val resolvedName = try {
            resolver.query(
                contentUri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        cursor.getString(nameIndex)
                    } else {
                        null
                    }
                } else {
                    null
                }
            }
        } catch (e: IllegalArgumentException) {
            Log.w(logTag, "failed to get display name for uri=$contentUri", e)
            null
        } catch (e: SecurityException) {
            Log.w(logTag, "failed to get display name for uri=$contentUri", e)
            null
        }

        resolvedContent["name"] = resolvedName ?: fallbackDisplayName(contentUri, contentType)
        val fileType = contentType.split("/", limit = 2)
        resolvedContent["type"] = fileType.getOrElse(0) { "" }
        resolvedContent["extension"] = fileType.getOrElse(1) { "" }
        if (contentType.startsWith("video")) {
            resolvedContent["data"] = contentUri.toString()
        } else if (contentType.startsWith("image")) {
            // Preserve transient-provider images after their URI grant expires.
            resolvedContent["data"] = if (contentUri.canBeRenderedFromUri()) {
                contentUri.toString()
            } else {
                resolver.encodeAsBase64(contentUri)
            }
        }
    }

    private fun Uri.canBeRenderedFromUri(): Boolean {
        return scheme == ContentResolver.SCHEME_FILE ||
            hasProviderAuthority(MediaStoreAuthority) ||
            hasProviderAuthority(MediaDocumentsAuthority)
    }

    private fun Uri.hasProviderAuthority(providerAuthority: String): Boolean {
        return host == providerAuthority
    }

    private fun ContentResolver.encodeAsBase64(contentUri: Uri): String {
        val imageBytes = openInputStream(contentUri)?.use { contentStream ->
            contentStream.readBytes()
        } ?: ByteArray(0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Base64.getEncoder().encodeToString(imageBytes)
        } else {
            android.util.Base64.encodeToString(
                imageBytes,
                android.util.Base64.DEFAULT
            )
        }
    }

    private fun fallbackDisplayName(contentUri: Uri, contentType: String): String {
        val lastSegment = contentUri.lastPathSegment?.substringAfterLast('/')
        if (!lastSegment.isNullOrBlank()) {
            return lastSegment
        }

        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(contentType)
        return if (extension.isNullOrBlank()) {
            "shared_${System.currentTimeMillis()}"
        } else {
            "shared_${System.currentTimeMillis()}.$extension"
        }
    }

    private fun resolveMimeType(intent: Intent, uri: Uri): String? {
        return intent.resolveType(context.contentResolver)
            ?: typeFromContentResolver(uri)
            ?: typeFromExtension(uri)
    }

    private fun typeFromContentResolver(uri: Uri): String? {
        return try {
            context.contentResolver.getType(uri)
        } catch (e: IllegalArgumentException) {
            Log.w(logTag, "failed to get content type for uri=$uri", e)
            null
        } catch (e: SecurityException) {
            Log.w(logTag, "failed to get content type for uri=$uri", e)
            null
        }
    }

    private fun typeFromExtension(uri: Uri): String? {
        val extension = uri.lastPathSegment
            ?.substringAfterLast('.', missingDelimiterValue = "")
            ?.lowercase(Locale.ROOT)
            ?.takeIf { it.isNotBlank() }
            ?: return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    private fun emitIntentAction(intent: Intent) {
        Handler(Looper.getMainLooper()).post {
            methodChannel.invokeMethod("getIntentAction", getIntentAction(intent))
        }
    }

    private fun getIntentAction(intent: Intent? = activity?.intent): HashMap<String, String> {
        val result = HashMap<String, String>()
        var resAction = IntentAction.valueOf("MAIN")
        if (intent != null) {
            val data: Uri? = intent.data
            val type: String? = intent.type
            when (intent.action) {
                Intent.ACTION_PICK -> {
                    type?.putMediaType(result)
                    intent.putAllowMultiple(result)
                    resAction = IntentAction.valueOf("PICK")
                }
                Intent.ACTION_GET_CONTENT -> {
                    type?.putMediaType(result)
                    intent.putAllowMultiple(result)
                    resAction = IntentAction.valueOf("PICK")
                }
                Intent.ACTION_EDIT -> {
                    resAction = IntentAction.valueOf("EDIT")
                }
                Intent.ACTION_VIEW -> {
                    if (data != null) {
                        result["uri"] = data.toString()
                        Log.i(logTag, " dataValueView=$data")
                    }
                    val resolvedType = data?.let { type ?: resolveMimeType(intent, it) }
                    if (data != null && resolvedType != null) {
                        try {
                            getResolvedContent(data, resolvedType, result)
                        } catch (e: Exception) {
                            Log.w(logTag, "failed to resolve intent data for uri=$data type=$resolvedType", e)
                        }
                    }
                    resAction = IntentAction.valueOf("VIEW")
                }
                else -> {
                    resAction = IntentAction.valueOf("MAIN")
                }
            }
        }
        result["action"] = resAction.toString()
        return result
    }

    private fun setResult(call: MethodCall, result: Result) {
        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
        if (uri == null) {
            result.error("setResult-args", "missing uri", null)
            return
        }
        setResultUris(listOf(uri), result)
    }

    private fun setResults(call: MethodCall, result: Result) {
        val uriStrings = call.argument<List<String>>("uris")
        if (uriStrings.isNullOrEmpty()) {
            result.error("setResults-args", "missing uris", null)
            return
        }
        setResultUris(uriStrings.map { Uri.parse(it) }, result)
    }

    private fun setResultUris(uris: List<Uri>, result: Result) {
        val shareableUris = uris.mapNotNull { getShareableUri(context, it) }
        if (shareableUris.isEmpty()) {
            result.error("setResults-args", "no shareable uris", null)
            return
        }
        val intent = Intent("io.ente.RESULT_ACTION")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val uri = shareableUris.first()
        intent.data = uri
        if (shareableUris.size > 1) {
            val clipData = ClipData.newUri(context.contentResolver, "media", uri)
            shareableUris.drop(1).forEach { clipData.addItem(ClipData.Item(it)) }
            intent.clipData = clipData
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        activity!!.setResult(Activity.RESULT_OK, intent)
        result.success(null)
        activity!!.finish()
    }

    private fun cancelResult(result: Result) {
        activity!!.setResult(Activity.RESULT_CANCELED)
        result.success(null)
        activity!!.finish()
    }

    private fun String.putMediaType(result: HashMap<String, String>) {
        val normalized = lowercase(Locale.ROOT)
        val mediaType = when {
            normalized.startsWith("image/") ||
                normalized == "vnd.android.cursor.dir/image" -> "image"
            normalized.startsWith("video/") ||
                normalized == "vnd.android.cursor.dir/video" -> "video"
            else -> null
        }
        if (mediaType != null) {
            result["type"] = mediaType
        }
        split("/", limit = 2).getOrNull(1)?.let { extension ->
            if (extension.isNotBlank() && extension != "*") {
                result["extension"] = extension
            }
        }
    }

    private fun Intent.putAllowMultiple(result: HashMap<String, String>) {
        if (getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)) {
            result["allowMultiple"] = "true"
        }
    }

    private fun readUriBytes(call: MethodCall, result: Result) {
        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
        if (uri == null) {
            result.error("readUriBytes-args", "missing uri", null)
            return
        }
        try {
            ioExecutor.execute {
                readUriBytesOnIoThread(uri, result)
            }
        } catch (e: RejectedExecutionException) {
            Log.w(logTag, "read uri executor is unavailable for uri=$uri", e)
            result.error("readUriBytes-unavailable", e.message, null)
        }
    }

    private fun readUriBytesOnIoThread(uri: Uri, result: Result) {
        try {
            val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                input.readBytesWithLimit(MaxReadUriBytes)
            }
            if (bytes == null) {
                mainHandler.post {
                    result.error("readUriBytes-open", "failed to open uri", null)
                }
                return
            }
            mainHandler.post {
                result.success(bytes)
            }
        } catch (e: UriTooLargeException) {
            Log.w(logTag, "uri exceeds read limit for uri=$uri", e)
            mainHandler.post {
                result.error("readUriBytes-too-large", e.message, null)
            }
        } catch (e: IllegalStateException) {
            val errorCode = if (uri.isRetryablePendingMediaStoreError(e)) {
                "readUriBytes-pending"
            } else {
                "readUriBytes-failed"
            }
            Log.w(logTag, "failed to read uri bytes for uri=$uri", e)
            mainHandler.post {
                result.error(errorCode, e.message, null)
            }
        } catch (e: Exception) {
            Log.w(logTag, "failed to read uri bytes for uri=$uri", e)
            mainHandler.post {
                result.error("readUriBytes-failed", e.message, null)
            }
        }
    }

    private fun Uri.isRetryablePendingMediaStoreError(error: IllegalStateException): Boolean {
        if (!hasProviderAuthority(MediaStoreAuthority)) {
            return false
        }

        // Only the ContentResolver pending check propagates this exception;
        // the FUSE pending/trashed check converts it to a generic I/O failure.
        return isMediaStorePendingItemError(error.message)
    }

    private fun InputStream.readBytesWithLimit(maxBytes: Long): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var totalBytes = 0L
        while (true) {
            val bytesRead = read(buffer)
            if (bytesRead == -1) {
                return output.toByteArray()
            }
            if (totalBytes + bytesRead > maxBytes) {
                throw UriTooLargeException(maxBytes)
            }
            output.write(buffer, 0, bytesRead)
            totalBytes += bytesRead
        }
    }

    private fun setAs(call: MethodCall, result: Result) {
        val title = "Set as"
        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
        val mimeType = call.argument<String>("mimeType")
        if (uri == null) {
            result.error("setAs-args", "missing arguments", null)
            return
        }
        val intent = Intent(Intent.ACTION_ATTACH_DATA)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .putExtra("mimeType", mimeType)
            .setDataAndType(getShareableUri(activity!!.applicationContext, uri), mimeType)
        val wallpaperIntent = Intent(intent)
            .setComponent(ComponentName(context, "io.ente.photos.WallpaperActivity"))
        val started = safeStartActivityChooser(title, intent, arrayOf(wallpaperIntent))
        result.success(started)
    }

    private fun openWith(call: MethodCall, result: Result) {
        val title = call.argument<String>("title")
        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
        val mimeType = call.argument<String>("mimeType")
        if (uri == null) {
            result.error("open-args", "missing arguments", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .setDataAndType(getShareableUri(activity!!.applicationContext, uri), mimeType)
        val started = safeStartActivityChooser(title, intent)

        result.success(started)
    }

    private fun edit(call: MethodCall, result: Result) {
        val title = call.argument<String>("title")
        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
        val mimeType = call.argument<String>("mimeType")
        if (uri == null) {
            result.error("edit-args", "missing arguments", null)
            return
        }

        val intent = Intent(Intent.ACTION_EDIT)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            .setDataAndType(getShareableUri(activity!!.applicationContext, uri), mimeType)
        val started = safeStartActivityChooser(title, intent)

        result.success(started)
    }

    private fun getShareableUri(context: Context, uri: Uri): Uri? {
        /* https://developer.android.com/training/secure-file-sharing/setup-sharing.html
        https://developer.android.com/training/secure-file-sharing/setup-sharing.html
         */
        return when (uri.scheme?.lowercase(Locale.ROOT)) {
            ContentResolver.SCHEME_FILE -> {
                uri.path?.let { path ->
                    FileProvider.getUriForFile(
                        context,
                        "${context.packageName}.file_provider",
                        File(path)
                    )
                }
            }
            else -> uri
        }
    }

    private fun safeStartActivityChooser(
        title: String?,
        intent: Intent,
        initialIntents: Array<Intent> = emptyArray(),
    ): Boolean {
        val currentActivity = activity ?: return false
        if (intent.resolveActivity(currentActivity.packageManager) == null) {
            Log.i(logTag, " intent=$intent resolved activity return null")
            //return false
        }
        try {
            val chooser = Intent.createChooser(intent, title)
            if (initialIntents.isNotEmpty()) {
                chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, initialIntents)
            }
            currentActivity.startActivity(chooser)
            return true
        } catch (e: SecurityException) {
            if (intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) {
                // in some environments, providing the write flag yields a `SecurityException`:
                // "UID `xyz` does not have permission to `content://xyz`"
                // so we retry without it
                Log.i(logTag, "retry intent=$intent without FLAG_GRANT_WRITE_URI_PERMISSION")
                intent.flags = intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION.inv()
                return safeStartActivityChooser(title, intent, initialIntents)
            } else {
                Log.w(logTag, "failed to start activity chooser for intent=$intent", e)
            }
        }
        return false
    }


    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        ioExecutor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
    }

    private fun detachFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        return true
    }

    override fun onNewIntent(intent: Intent): Boolean {
        activity?.setIntent(intent)
        emitIntentAction(intent)
        return false
    }

    private companion object {
        private const val MediaStoreAuthority = "media"
        private const val MediaDocumentsAuthority = "com.android.providers.media.documents"
        private const val MaxReadUriBytes = 100L * 1024L * 1024L
    }

    private class UriTooLargeException(maxBytes: Long) :
        IOException("uri content exceeds ${maxBytes / (1024L * 1024L)} MiB")
}
