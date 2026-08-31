package io.ente.photos.platform.flutter

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.ente.photos.platform.devicefoldertransfer.DeviceFolderTransferService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.ArrayDeque
import java.util.concurrent.Executors

internal class DeviceFolderTransferChannelAdapter : MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private lateinit var service: DeviceFolderTransferService
    private lateinit var methodChannel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var consentedTransfer: (() -> Unit)? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingLocalIDs: List<String> = emptyList()
    private var pendingConsentBatches: ArrayDeque<List<android.net.Uri>>? = null
    private var isConsentRequestInProgress = false
    private var transferExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var isDetached = false
    @Volatile
    private var attachmentGeneration = 0

    fun attach(binding: FlutterPlugin.FlutterPluginBinding) {
        isDetached = false
        attachmentGeneration++
        if (transferExecutor.isShutdown) transferExecutor = Executors.newSingleThreadExecutor()
        service = DeviceFolderTransferService(binding.applicationContext)
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
    }

    fun attachActivity(binding: ActivityPluginBinding) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        startPendingConsentRequest()
    }

    fun detachActivity(cancelPendingConsent: Boolean) {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
        if (cancelPendingConsent) {
            if (pendingResult != null) completeWithFailures("cancelled")
        } else {
            isConsentRequestInProgress = false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        when (call.method) {
            "deviceFolderTransfer.supportedOperations" -> {
                result.success(service.supportedOperations())
            }
            "deviceFolderTransfer.eligibleDestinations" -> {
                val operation = arguments["operation"] as? String
                val ids = arguments["candidateFolderIDs"] as? List<*> ?: emptyList<Any>()
                val sourceLocalIDs = arguments["sourceLocalIDs"] as? List<*> ?: emptyList<Any>()
                val generation = attachmentGeneration
                transferExecutor.execute {
                    try {
                        val eligibleIDs = service.eligibleDestinationIDs(
                            operation,
                            arguments["sourceFolderID"] as? String ?: "",
                            ids.filterIsInstance<String>(),
                            sourceLocalIDs.filterIsInstance<String>(),
                        )
                        postToMain(generation) { result.success(eligibleIDs) }
                    } catch (error: Exception) {
                        Log.e(
                            TAG,
                            "Could not load eligible device-folder destinations operation=$operation sourceCount=${sourceLocalIDs.size}",
                            error,
                        )
                        postToMain(generation) {
                            result.error(
                                "device_folder_transfer_failed",
                                error.message,
                                null,
                            )
                        }
                    }
                }
            }
            "deviceFolderTransfer.transfer" -> {
                val operation = arguments["operation"] as? String
                val source = arguments["sourceFolderID"] as? String
                val target = arguments["targetFolderID"] as? String
                val ids = (arguments["sourceLocalIDs"] as? List<*>)?.filterIsInstance<String>()
                if (operation == null || source == null || target == null || ids == null) {
                    result.error("device_folder_transfer_invalid_arguments", null, null)
                } else {
                    requestConsentThenTransfer(
                        operation,
                        source,
                        target,
                        ids,
                        result,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    fun detach() {
        detachActivity(cancelPendingConsent = true)
        isDetached = true
        attachmentGeneration++
        transferExecutor.shutdown()
        methodChannel.setMethodCallHandler(null)
    }

    private fun requestConsentThenTransfer(
        operation: String,
        source: String,
        target: String,
        ids: List<String>,
        result: MethodChannel.Result,
    ) {
        if (pendingResult != null) {
            result.error("device_folder_transfer_in_progress", "Another device folder transfer is in progress", null)
            return
        }
        pendingResult = result
        pendingLocalIDs = ids
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || operation == "copy") {
            runTransfer(
                operation,
                source,
                target,
                ids,
                result,
            )
            return
        }
        val generation = attachmentGeneration
        pendingConsentBatches = ArrayDeque()
        transferExecutor.execute {
            try {
                val consentRequests = service.moveConsentRequests(source, target, ids)
                postToMain(generation) {
                    if (pendingResult !== result) return@postToMain
                    if (consentRequests.writeURIs.isEmpty()) {
                        clearPendingConsent()
                        runTransfer(
                            operation,
                            source,
                            target,
                            ids,
                            result,
                        )
                        return@postToMain
                    }
                    consentedTransfer = {
                        runTransfer(
                            operation,
                            source,
                            target,
                            ids,
                            result,
                        )
                    }
                    pendingConsentBatches?.addAll(
                        consentRequests.writeURIs.chunked(MAX_CONSENT_URI_COUNT),
                    )
                    startPendingConsentRequest()
                }
            } catch (error: Exception) {
                Log.e(
                    TAG,
                    "Could not prepare MediaStore write consent operation=$operation count=${ids.size}",
                    error,
                )
                postToMain(generation) {
                    completeWithError(error)
                }
            }
        }
    }

    private fun startPendingConsentRequest() {
        if (isConsentRequestInProgress) return
        val uris = pendingConsentBatches?.firstOrNull() ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            completeWithFailures("unsupported")
            return
        }
        val host = activity
        if (host == null) {
            return
        }
        try {
            isConsentRequestInProgress = true
            host.startIntentSenderForResult(
                MediaStore.createWriteRequest(host.contentResolver, uris).intentSender,
                REQUEST_WRITE_ACCESS,
                null,
                0,
                0,
                0,
            )
        } catch (error: Exception) {
            Log.e(TAG, "Could not request MediaStore write consent count=${uris.size}", error)
            isConsentRequestInProgress = false
            completeWithFailures("failed")
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_WRITE_ACCESS || !isConsentRequestInProgress) return false
        val result = pendingResult ?: return false
        isConsentRequestInProgress = false
        if (resultCode == Activity.RESULT_OK) {
            pendingConsentBatches?.let { batches ->
                if (batches.isNotEmpty()) batches.removeFirst()
            }
            if (pendingConsentBatches?.isNotEmpty() == true) {
                startPendingConsentRequest()
            } else {
                val transfer = consentedTransfer
                clearPendingConsent()
                transfer?.invoke()
            }
        } else {
            completeWithFailures("cancelled")
        }
        return true
    }

    private fun completeWithFailures(failure: String) {
        val result = pendingResult ?: return
        val localIDs = pendingLocalIDs
        clearPending()
        result.success(
            mapOf(
                "destinations" to emptyMap<String, Map<String, String>>(),
                "failures" to localIDs.associateWith { failure },
            ),
        )
    }

    private fun clearPending() {
        pendingResult = null
        pendingLocalIDs = emptyList()
        clearPendingConsent()
    }

    private fun clearPendingConsent() {
        consentedTransfer = null
        pendingConsentBatches = null
        isConsentRequestInProgress = false
    }

    private fun completeWithError(error: Exception) {
        val result = pendingResult ?: return
        clearPending()
        result.error(
            "device_folder_transfer_failed",
            error.message,
            null,
        )
    }

    private fun runTransfer(
        operation: String,
        source: String,
        target: String,
        ids: List<String>,
        result: MethodChannel.Result,
    ) {
        val generation = attachmentGeneration
        transferExecutor.execute {
            try {
                val transferResult = service.transfer(
                    operation,
                    source,
                    target,
                    ids,
                )
                finishTransfer(result, generation) { it.success(transferResult) }
            } catch (error: Exception) {
                Log.e(
                    TAG,
                    "Could not execute device-folder transfer operation=$operation count=${ids.size}",
                    error,
                )
                finishTransfer(result, generation) {
                    it.error("device_folder_transfer_failed", error.message, null)
                }
            }
        }
    }

    private fun finishTransfer(
        result: MethodChannel.Result,
        generation: Int,
        completion: (MethodChannel.Result) -> Unit,
    ) {
        mainHandler.post {
            if (pendingResult !== result) return@post
            clearPending()
            if (!isDetached && generation == attachmentGeneration) completion(result)
        }
    }

    private fun postToMain(generation: Int = attachmentGeneration, action: () -> Unit) {
        mainHandler.post {
            if (!isDetached && generation == attachmentGeneration) action()
        }
    }

    private companion object {
        const val METHOD_CHANNEL = "io.ente.photos.platform/device_folder_transfer"
        const val REQUEST_WRITE_ACCESS = 8301
        const val MAX_CONSENT_URI_COUNT = 1900
        const val TAG = "DeviceFolderTransferChannel"
    }
}
