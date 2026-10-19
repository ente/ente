package io.ente.native_video_editor.core

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.ExperimentalApi
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Size
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.muxer.BufferInfo
import androidx.media3.muxer.Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.roundToLong

@UnstableApi
class VideoExportEngine(
    private val context: Context,
    private val metadataReader: VideoMetadataReader
) {
    suspend fun processVideo(
        request: VideoEditRequest,
        onProgress: ((Float) -> Unit)? = null
    ): VideoEditResult = withContext(Dispatchers.IO) {
        val inputFile = File(request.inputPath).canonicalFile
        val outputFile = File(request.outputPath).canonicalFile
        require(inputFile.isFile && inputFile != outputFile) {
            "Input must be a video file and output must be a different path"
        }

        try {
            val clipRange = resolveVideoClipRangeUs(
                videoDurationUs = getVideoTrackDurationUs(inputFile.path),
                requestedStartUs = request.trimStartMs?.times(1_000L),
                requestedEndUs = request.trimEndMs?.times(1_000L)
            )
            val mediaItem = buildMediaItem(inputFile, clipRange)
            val videoInfo = request.crop?.let { metadataReader.read(inputFile.path) }
            val effects = buildVideoEffects(videoInfo, request.crop, request.rotateDegrees)
            val audioProcessors = if (request.speed != 1f) {
                listOf(SonicAudioProcessor().apply { setPitch(1f / request.speed) })
            } else {
                emptyList()
            }
            val editedMediaItem = EditedMediaItem.Builder(mediaItem).apply {
                if (request.speed != 1f) {
                    setSpeed(ConstantSpeedProvider(request.speed))
                }
                if (effects.isNotEmpty() || audioProcessors.isNotEmpty()) {
                    setEffects(Effects(audioProcessors, effects))
                }
            }.build()
            @Suppress("DEPRECATION")
            val sequence = EditedMediaItemSequence.Builder(listOf(editedMediaItem)).build()
            val composition = Composition.Builder(listOf(sequence)).build()

            val exportResult = withContext(Dispatchers.Main) {
                export(
                    composition = composition,
                    outputPath = outputFile.path,
                    transcodeVideo = effects.isNotEmpty() || request.speed != 1f,
                    optimizeTrim = request.trimStartMs != null &&
                        effects.isEmpty() &&
                        request.speed == 1f,
                    maxDurationUs = if (request.speed != 1f) {
                        ((clipRange.endUs - clipRange.startUs) / request.speed.toDouble()).roundToLong()
                    } else {
                        null
                    },
                    onProgress = onProgress
                )
            }
            require(outputFile.isFile && outputFile.length() > 0) {
                "Output file was not created"
            }
            val isReEncoded = when (exportResult.videoConversionProcess) {
                ExportResult.CONVERSION_PROCESS_TRANSCODED,
                ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED -> true
                else -> false
            }
            VideoEditResult(request.outputPath, isReEncoded)
        } catch (error: CancellationException) {
            outputFile.delete()
            throw error
        } catch (error: Exception) {
            outputFile.delete()
            throw VideoProcessingException("Video processing failed: ${error.message}", error)
        }
    }

    private fun buildMediaItem(
        inputFile: File,
        clipRange: VideoClipRangeUs
    ): MediaItem = MediaItem.Builder()
        .setUri(Uri.fromFile(inputFile))
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionUs(clipRange.startUs)
                .setEndPositionUs(clipRange.endUs)
                .setStartsAtKeyFrame(false)
                .build()
        )
        .build()

    private fun buildVideoEffects(
        videoInfo: VideoMetadata?,
        crop: VideoCrop?,
        rotateDegrees: Int?
    ): List<Effect> = buildList {
        val cropSize = crop?.let {
            val video = requireNotNull(videoInfo)
            val displayWidth = video.displayWidth
            val displayHeight = video.displayHeight
            require(displayWidth > 0 && displayHeight > 0) {
                "Video dimensions are unavailable"
            }
            require(
                it.x.toLong() + it.width <= displayWidth &&
                    it.y.toLong() + it.height <= displayHeight
            ) { "Crop rectangle exceeds the displayed video" }

            add(
                Crop(
                    -1f + 2f * it.x / displayWidth,
                    -1f + 2f * (it.x + it.width) / displayWidth,
                    1f - 2f * (it.y + it.height) / displayHeight,
                    1f - 2f * it.y / displayHeight
                )
            )
            Size(it.width, it.height)
        }

        if (rotateDegrees != null && rotateDegrees != 0) {
            add(
                ScaleAndRotateTransformation.Builder()
                    .setRotationDegrees(-rotateDegrees.toFloat())
                    .build()
            )
        }

        if (cropSize != null) {
            val swapsDimensions = rotateDegrees == 90 || rotateDegrees == 270
            add(
                Presentation.createForWidthAndHeight(
                    if (swapsDimensions) cropSize.height else cropSize.width,
                    if (swapsDimensions) cropSize.width else cropSize.height,
                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                )
            )
        }
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalApi::class])
    private suspend fun export(
        composition: Composition,
        outputPath: String,
        transcodeVideo: Boolean,
        optimizeTrim: Boolean,
        maxDurationUs: Long?,
        onProgress: ((Float) -> Unit)?
    ): ExportResult = coroutineScope {
        var progressJob: Job? = null
        try {
            suspendCancellableCoroutine { continuation ->
                val transformerBuilder = Transformer.Builder(context)
                if (maxDurationUs != null) {
                    transformerBuilder.setMuxerFactory(DurationLimitedMuxerFactory(maxDurationUs))
                }
                if (transcodeVideo) {
                    transformerBuilder.setVideoMimeType(MimeTypes.VIDEO_H264)
                }
                if (optimizeTrim) {
                    transformerBuilder.experimentalSetTrimOptimizationEnabled(true)
                }
                val transformer = transformerBuilder
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult
                        ) {
                            if (continuation.isActive) {
                                onProgress?.invoke(1f)
                                continuation.resumeWith(Result.success(exportResult))
                            }
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            if (continuation.isActive) {
                                continuation.resumeWith(Result.failure(exportException))
                            }
                        }
                    })
                    .build()

                continuation.invokeOnCancellation {
                    Handler(Looper.getMainLooper()).post(transformer::cancel)
                }
                transformer.start(composition, outputPath)
                progressJob = launch {
                    val holder = ProgressHolder()
                    while (isActive && continuation.isActive) {
                        if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                            onProgress?.invoke(holder.progress / 100f)
                        }
                        delay(100)
                    }
                }
            }
        } finally {
            progressJob?.cancel()
        }
    }

    private fun getVideoTrackDurationUs(videoPath: String): Long {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(videoPath)
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mimeType = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mimeType.startsWith("video/")) {
                    require(format.containsKey(MediaFormat.KEY_DURATION)) {
                        "Video track duration is unavailable"
                    }
                    return format.getLong(MediaFormat.KEY_DURATION).also {
                        require(it > 0) { "Video track duration is invalid" }
                    }
                }
            }
            throw IllegalArgumentException("Input has no video track")
        } finally {
            extractor.release()
        }
    }
}

@UnstableApi
private class DurationLimitedMuxerFactory(
    private val durationUs: Long,
    private val factory: Muxer.Factory = InAppMp4Muxer.Factory().setVideoDurationUs(durationUs)
) : Muxer.Factory by factory {
    override fun create(path: String): Muxer {
        val muxer = factory.create(path)
        return object : Muxer by muxer {
            override fun writeSampleData(trackId: Int, byteBuffer: ByteBuffer, bufferInfo: BufferInfo) {
                if (bufferInfo.presentationTimeUs < durationUs) {
                    muxer.writeSampleData(trackId, byteBuffer, bufferInfo)
                }
            }
        }
    }
}

@UnstableApi
private class ConstantSpeedProvider(private val speed: Float) : SpeedProvider {
    override fun getSpeed(timeUs: Long): Float = speed

    override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
}

internal data class VideoClipRangeUs(val startUs: Long, val endUs: Long)

internal fun resolveVideoClipRangeUs(
    videoDurationUs: Long,
    requestedStartUs: Long?,
    requestedEndUs: Long?
): VideoClipRangeUs {
    val startUs = requestedStartUs ?: 0L
    val endUs = minOf(requestedEndUs ?: videoDurationUs, videoDurationUs)
    require(startUs < endUs) {
        "Trim range does not overlap the video track"
    }
    return VideoClipRangeUs(startUs, endUs)
}

class VideoProcessingException(message: String, cause: Throwable? = null) : Exception(message, cause)
