package io.ente.native_video_editor

import android.util.Log
import androidx.annotation.NonNull
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.ExportException
import io.ente.native_video_editor.core.VideoExportEngine
import io.ente.native_video_editor.core.VideoFrameExtractor
import io.ente.native_video_editor.core.VideoMetadataReader
import io.ente.native_video_editor.core.VideoCrop
import io.ente.native_video_editor.core.VideoEditRequest
import io.ente.native_video_editor.core.VideoEditResult
import io.ente.native_video_editor.core.VideoFrameExtractionResult
import io.ente.native_video_editor.core.VideoFramePolicy
import io.ente.native_video_editor.core.VideoFrameRequest
import io.ente.native_video_editor.core.VideoMetadata
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

@UnstableApi
class NativeVideoEditorPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private var progressEventSink: EventChannel.EventSink? = null
    private var scope = newPluginScope()
    private var currentExportJob: Job? = null
    private val frameJobs = mutableMapOf<String, Job>()
    private lateinit var metadataReader: VideoMetadataReader
    private lateinit var frameExtractor: VideoFrameExtractor
    private lateinit var videoExporter: VideoExportEngine

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        if (!scope.isActive) scope = newPluginScope()

        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        channel.setMethodCallHandler(this)
        progressChannel = EventChannel(binding.binaryMessenger, PROGRESS_CHANNEL)
        progressChannel.setStreamHandler(this)

        metadataReader = VideoMetadataReader()
        frameExtractor = VideoFrameExtractor(binding.applicationContext, metadataReader)
        videoExporter = VideoExportEngine(binding.applicationContext, metadataReader)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        val pluginScope = scope
        if (!pluginScope.isActive) {
            result.error("PLUGIN_DETACHED", "Native video editor is detached", null)
            return
        }

        when (call.method) {
            "getVideoInfo" -> inspectVideo(call, result, pluginScope)
            "extractFrame" -> extractSingleFrame(call, result, pluginScope)
            "extractTimeline" -> extractTimeline(call, result, pluginScope)
            "cancelFrameExtraction" -> cancelFrameExtraction(call, result, pluginScope)
            "processVideo" -> processVideo(call, result, pluginScope)
            "cancelProcessing" -> cancelProcessing(result, pluginScope)
            else -> result.notImplemented()
        }
    }

    private fun inspectVideo(call: MethodCall, result: Result, pluginScope: CoroutineScope) {
        val videoPath = call.argument<String>("videoPath")
        if (videoPath.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing video path", null)
            return
        }

        pluginScope.launch {
            try {
                val info = withContext(Dispatchers.IO) { metadataReader.read(videoPath) }
                if (canReply(pluginScope)) result.success(info.toChannelMap())
            } catch (error: LinkageError) {
                replyError(result, "INFO_LINKAGE_ERROR", "Get video info", error, pluginScope)
            } catch (error: Exception) {
                replyError(result, "INFO_ERROR", "Get video info", error, pluginScope)
            }
        }
    }

    private fun extractSingleFrame(
        call: MethodCall,
        result: Result,
        pluginScope: CoroutineScope
    ) {
        val outputPath = call.argument<String>("outputPath")
        val positionMs = call.argument<Number>("positionMs")?.toLong()
        if (outputPath.isNullOrBlank() || positionMs == null) {
            result.error("INVALID_ARGS", "Invalid frame arguments", null)
            return
        }
        startFrameExtraction(
            call,
            result,
            UUID.randomUUID().toString(),
            listOf(outputPath),
            listOf(positionMs),
            pluginScope
        )
    }

    private fun extractTimeline(
        call: MethodCall,
        result: Result,
        pluginScope: CoroutineScope
    ) {
        val requestId = call.argument<String>("requestId")
        val outputPaths = call.argument<List<String>>("outputPaths")
        val positionsMs = call.argument<List<Number>>("positionsMs")?.map(Number::toLong)
        if (requestId.isNullOrBlank() || outputPaths == null || positionsMs == null) {
            result.error("INVALID_ARGS", "Invalid timeline arguments", null)
            return
        }
        startFrameExtraction(call, result, requestId, outputPaths, positionsMs, pluginScope)
    }

    private fun startFrameExtraction(
        call: MethodCall,
        result: Result,
        requestId: String,
        outputPaths: List<String>,
        positionsMs: List<Long>,
        pluginScope: CoroutineScope
    ) {
        if (frameJobs.containsKey(requestId)) {
            result.error("DUPLICATE_REQUEST", "Frame request ID is already active", requestId)
            return
        }
        val request = parseFrameRequest(call, outputPaths, positionsMs)
        if (request == null) {
            result.error("INVALID_ARGS", "Invalid frame extraction arguments", null)
            return
        }

        val job = pluginScope.launch(start = CoroutineStart.LAZY) {
            try {
                val extraction = frameExtractor.extract(request)
                if (canReply(pluginScope)) result.success(extraction.toChannelMap())
            } catch (error: CancellationException) {
                replyError(
                    result,
                    "FRAME_CANCELLED",
                    "Frame extraction was cancelled",
                    error,
                    pluginScope,
                    requestId
                )
            } catch (error: LinkageError) {
                replyError(
                    result,
                    "FRAME_LINKAGE_ERROR",
                    "Frame extraction",
                    error,
                    pluginScope
                )
            } catch (error: Exception) {
                replyError(
                    result,
                    "FRAME_EXTRACTION_ERROR",
                    "Frame extraction",
                    error,
                    pluginScope
                )
            } finally {
                frameJobs.remove(requestId)
            }
        }
        frameJobs[requestId] = job
        job.start()
    }

    private fun cancelFrameExtraction(
        call: MethodCall,
        result: Result,
        pluginScope: CoroutineScope
    ) {
        val requestId = call.argument<String>("requestId")
        if (requestId.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing frame request ID", null)
            return
        }
        val job = frameJobs[requestId]
        if (job == null) {
            result.success(null)
            return
        }
        pluginScope.launch {
            job.cancelAndJoin()
            if (canReply(pluginScope)) result.success(null)
        }
    }

    private fun processVideo(call: MethodCall, result: Result, pluginScope: CoroutineScope) {
        if (currentExportJob?.isActive == true) {
            result.error("INVALID_ARGS", "Invalid or concurrent export request", null)
            return
        }
        val request = parseEditRequest(call)
        if (request == null) {
            result.error("INVALID_ARGS", "Invalid video processing arguments", null)
            return
        }

        val job = pluginScope.launch(start = CoroutineStart.LAZY) {
            try {
                val export = videoExporter.processVideo(request) { progress ->
                    if (canReply(pluginScope)) progressEventSink?.success(progress)
                }
                if (canReply(pluginScope)) result.success(export.toChannelMap())
            } catch (error: LinkageError) {
                replyError(
                    result,
                    "PROCESS_LINKAGE_ERROR",
                    "Process video",
                    error,
                    pluginScope
                )
            } catch (error: CancellationException) {
                replyError(
                    result,
                    "PROCESS_CANCELLED",
                    "Process video",
                    error,
                    pluginScope
                )
            } catch (error: Exception) {
                replyError(result, "PROCESS_ERROR", "Process video", error, pluginScope)
            } finally {
                if (currentExportJob == coroutineContext[Job]) currentExportJob = null
            }
        }
        currentExportJob = job
        job.start()
    }

    private fun cancelProcessing(result: Result, pluginScope: CoroutineScope) {
        val job = currentExportJob
        if (job == null) {
            result.success(null)
            return
        }
        pluginScope.launch {
            job.cancelAndJoin()
            if (canReply(pluginScope)) result.success(null)
        }
    }

    private fun parseFrameRequest(
        call: MethodCall,
        outputPaths: List<String>,
        positionsMs: List<Long>
    ): VideoFrameRequest? = runCatching {
        VideoFrameRequest(
            inputPath = requireNotNull(call.argument<String>("inputPath")),
            outputPaths = outputPaths,
            positionsMs = positionsMs,
            maxWidth = requireNotNull(call.argument<Int>("maxWidth")),
            maxHeight = requireNotNull(call.argument<Int>("maxHeight")),
            quality = requireNotNull(call.argument<Int>("quality")),
            policy = when (call.argument<String>("policy")) {
                "precise" -> VideoFramePolicy.PRECISE
                "nearestSync" -> VideoFramePolicy.NEAREST_SYNC
                else -> error("Invalid frame policy")
            }
        )
    }.getOrNull()

    private fun parseEditRequest(call: MethodCall): VideoEditRequest? = runCatching {
        val cropValues = listOf(
            call.argument<Int>("cropX"),
            call.argument<Int>("cropY"),
            call.argument<Int>("cropWidth"),
            call.argument<Int>("cropHeight")
        )
        require(cropValues.all { it == null } || cropValues.all { it != null })
        val crop = if (cropValues.first() == null) {
            null
        } else {
            VideoCrop(
                cropValues[0]!!,
                cropValues[1]!!,
                cropValues[2]!!,
                cropValues[3]!!
            )
        }
        VideoEditRequest(
            inputPath = requireNotNull(call.argument<String>("inputPath")),
            outputPath = requireNotNull(call.argument<String>("outputPath")),
            trimStartMs = call.argument<Number>("trimStartMs")?.toLong(),
            trimEndMs = call.argument<Number>("trimEndMs")?.toLong(),
            rotateDegrees = call.argument<Int>("rotateDegrees"),
            crop = crop,
            speed = call.argument<Number>("speed")?.toFloat() ?: 1f
        )
    }.getOrNull()

    private suspend fun replyError(
        result: Result,
        code: String,
        operation: String,
        error: Throwable,
        pluginScope: CoroutineScope,
        details: Any? = null
    ) {
        Log.e(TAG, "$operation failed", error)
        withContext(NonCancellable + Dispatchers.Main.immediate) {
            if (canReply(pluginScope)) {
                result.error(
                    code,
                    if (code.endsWith("CANCELLED")) operation else error.message ?: operation,
                    details ?: buildErrorDetails(error)
                )
            }
        }
    }

    private fun canReply(pluginScope: CoroutineScope): Boolean = pluginScope.isActive

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        progressEventSink = null
        channel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
        scope.cancel()
        currentExportJob = null
        frameJobs.clear()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (scope.isActive) progressEventSink = events
    }

    override fun onCancel(arguments: Any?) {
        progressEventSink = null
    }

    private fun VideoMetadata.toChannelMap(): Map<String, Any> = buildMap {
        put("duration", durationMs)
        put("width", width)
        put("height", height)
        put("displayWidth", displayWidth)
        put("displayHeight", displayHeight)
        put("rotation", rotationDegrees)
        bitrate?.let { put("bitrate", it) }
        frameRate?.let { put("frameRate", it) }
    }

    private fun VideoFrameExtractionResult.toChannelMap(): Map<String, Any> = mapOf(
        "videoInfo" to videoInfo.toChannelMap(),
        "frames" to frames.map {
            mapOf("outputPath" to it.outputPath, "width" to it.width, "height" to it.height)
        }
    )

    private fun VideoEditResult.toChannelMap(): Map<String, Any> = mapOf(
        "outputPath" to outputPath,
        "isReEncoded" to isReEncoded
    )

    private fun buildErrorDetails(error: Throwable): Map<String, Any?> {
        val details = mutableMapOf<String, Any?>(
            "type" to error::class.java.simpleName,
            "message" to (error.message ?: "")
        )
        val exportException = when {
            error is ExportException -> error
            error.cause is ExportException -> error.cause as ExportException
            else -> null
        }
        exportException?.let { details["errorCode"] = it.errorCode }
        (error.cause ?: exportException?.cause)?.let {
            details["causeType"] = it::class.java.simpleName
            details["causeMessage"] = it.message ?: ""
        }
        return details
    }

    private companion object {
        const val TAG = "NativeVideoEditorPlugin"
        const val METHOD_CHANNEL = "native_video_editor"
        const val PROGRESS_CHANNEL = "native_video_editor/progress"

        fun newPluginScope() = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }
}
