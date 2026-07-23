package io.ente.native_video_editor

import android.content.Context
import android.util.Log
import android.net.Uri
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Size
import androidx.media3.effect.*
import androidx.media3.transformer.*
import kotlinx.coroutines.*
import java.io.File
import java.util.concurrent.CountDownLatch
import kotlin.math.roundToInt

/**
 * Processor using Media3 Transformer for efficient video editing operations.
 * Handles trim, rotate, and crop operations with proper effect chaining.
 */
class Media3TransformerProcessor(private val context: Context) {
    companion object {
        private const val TAG = "Media3Transformer"

        // Logging levels for debugging (enabled only for debug builds when available)
        private val IS_DEBUG_BUILD: Boolean = try {
            val field = Class.forName("io.ente.native_video_editor.BuildConfig")
                .getField("DEBUG")
            field.getBoolean(null)
        } catch (_: Exception) {
            false
        }

        private val LOG_VERBOSE = IS_DEBUG_BUILD
        private val LOG_PROGRESS = IS_DEBUG_BUILD
        private val LOG_ERRORS = true  // Keep error logging enabled
        private const val ROTATION_90 = 90
        private const val ROTATION_270 = 270
    }

    /**
     * Process video with multiple transformations in a single pass
     */
    suspend fun processVideo(
        inputPath: String,
        outputPath: String,
        trimStartMs: Long? = null,
        trimEndMs: Long? = null,
        rotateDegrees: Int? = null,
        cropX: Int? = null,
        cropY: Int? = null,
        cropWidth: Int? = null,
        cropHeight: Int? = null,
        onProgress: ((Float) -> Unit)? = null
    ): ProcessingResult = withContext(Dispatchers.Main) {
        val startTime = System.currentTimeMillis()
        val latch = CountDownLatch(1)
        var processingError: Exception? = null
        var hasVideoEffects = false

        logVerbose("Starting video processing:")
        logVerbose("  Input: $inputPath")
        logVerbose("  Output: $outputPath")
        logVerbose("  Trim: ${if (trimStartMs != null) "$trimStartMs-$trimEndMs ms" else "none"}")
        logVerbose("  Rotate: ${rotateDegrees ?: "none"} degrees")
        logVerbose("  Crop: ${if (cropX != null) "[$cropX,$cropY ${cropWidth}x$cropHeight]" else "none"}")

        try {
            // Get video info first
            val videoInfo = getVideoInfo(inputPath)
            val originalWidth = videoInfo.width
            val originalHeight = videoInfo.height
            val originalRotation = videoInfo.rotation

            logVerbose("Original video: ${originalWidth}x$originalHeight, rotation=$originalRotation")

            // Build MediaItem with optional clipping
            val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(File(inputPath)))

            if (trimStartMs != null && trimEndMs != null) {
                logVerbose("Applying trim: $trimStartMs-$trimEndMs ms")
                mediaItemBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(trimStartMs)
                        .setEndPositionMs(trimEndMs)
                        .setStartsAtKeyFrame(false) // Allow precise cuts
                        .build()
                )
            }

            val mediaItem = mediaItemBuilder.build()

            // Build effects list
            val videoEffects = mutableListOf<Effect>()

            // Add crop effect if needed BEFORE rotation
            // Flutter sends crop coordinates in display space.
            // Like FFmpeg and iOS, we'll use these coordinates directly without transformation.
            var outDimsFromCrop: Size? = null
            if (cropX != null && cropY != null && cropWidth != null && cropHeight != null) {
                logVerbose("Crop input: x=$cropX, y=$cropY, w=$cropWidth, h=$cropHeight")
                logVerbose("Video dims: ${originalWidth}x$originalHeight, rotation=$originalRotation")

                // Use crop coordinates as-is, just like FFmpeg does
                // No special treatment for metadata rotation
                val fileX = cropX
                val fileY = cropY
                val fileW = cropWidth
                val fileH = cropHeight

                logVerbose("Using crop coordinates as-is: x=$fileX, y=$fileY, w=$fileW, h=$fileH")

                // When video has rotation metadata, swap dimensions for crop fraction calculation
                // This is because Flutter sends display-space coordinates (after rotation)
                val effectiveWidth: Int
                val effectiveHeight: Int
                if (originalRotation == 90 || originalRotation == 270) {
                    effectiveWidth = originalHeight
                    effectiveHeight = originalWidth
                    logVerbose("Video has 90/270 rotation, swapping dimensions for crop calculation: ${effectiveWidth}x$effectiveHeight")
                } else {
                    effectiveWidth = originalWidth
                    effectiveHeight = originalHeight
                }

                // Calculate crop as a fraction of the effective video dimensions
                val cropLeftFraction = fileX.toFloat() / effectiveWidth
                val cropRightFraction = (fileX + fileW).toFloat() / effectiveWidth
                val cropTopFraction = fileY.toFloat() / effectiveHeight
                val cropBottomFraction = (fileY + fileH).toFloat() / effectiveHeight

                logVerbose("Crop fractions: L=$cropLeftFraction, R=$cropRightFraction, T=$cropTopFraction, B=$cropBottomFraction")

                // Use Crop effect with NDC coordinates (-1 to 1)
                val ndcLeft = -1f + 2f * cropLeftFraction
                val ndcRight = -1f + 2f * cropRightFraction
                val ndcBottom = 1f - 2f * cropBottomFraction
                val ndcTop = 1f - 2f * cropTopFraction

                logVerbose("NDC coordinates: left=$ndcLeft, right=$ndcRight, bottom=$ndcBottom, top=$ndcTop")
                logVerbose("Expected crop output: ${cropWidth}x$cropHeight pixels")

                val cropEffect = Crop(
                    /* left = */ ndcLeft,
                    /* right = */ ndcRight,
                    /* bottom = */ ndcBottom,
                    /* top = */ ndcTop
                )

                // Preserve output dimensions from the crop
                outDimsFromCrop = Size(cropWidth, cropHeight)

                videoEffects.add(cropEffect)
                hasVideoEffects = true
            }

            // Add rotation effect AFTER crop
            if (rotateDegrees != null && rotateDegrees != 0) {
                val normalizedDegrees = rotateDegrees % 360
                logVerbose("Adding rotation effect: $normalizedDegrees degrees")

                // Validate rotation degrees
                if (normalizedDegrees !in listOf(0, 90, 180, 270)) {
                    throw IllegalArgumentException("Rotation degrees must be 0, 90, 180, or 270")
                }

                // Use ScaleAndRotateTransformation for proper rotation support
                // Media3 uses positive degrees for clockwise rotation
                val rotationEffect = ScaleAndRotateTransformation.Builder()
                    .setRotationDegrees(normalizedDegrees.toFloat())
                    .build()

                videoEffects.add(rotationEffect)
                logVerbose("Added ScaleAndRotateTransformation with rotation: $normalizedDegrees degrees (clockwise)")

                hasVideoEffects = true
            }

            // Add Presentation effect to set output dimensions
            // Base output on the file-space crop dimensions we actually applied.
            if (outDimsFromCrop != null) {
                var outputWidth = outDimsFromCrop!!.width
                var outputHeight = outDimsFromCrop!!.height

                // If a user-requested rotation (not metadata) is applied after crop,
                // swap output dimensions for 90/270 degrees.
                if (rotateDegrees != null && (rotateDegrees % 180) != 0) {
                    val tmp = outputWidth
                    outputWidth = outputHeight
                    outputHeight = tmp
                }

                val presentationEffect = Presentation.createForWidthAndHeight(
                    outputWidth,
                    outputHeight,
                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                )
                videoEffects.add(presentationEffect)
            }

            // Configure Transformer
            val transformerBuilder = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264) // Use H.264 for compatibility
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        logVerbose("Export completed successfully")
                        logVerbose("Export result: duration=${exportResult.approximateDurationMs}ms, " +
                                  "size=${exportResult.fileSizeBytes} bytes")
                        latch.countDown()
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        logError(
                            "Export failed (code=${exportException.errorCode}, type=${exportException::class.java.simpleName})",
                            exportException
                        )
                        exportException.cause?.let { cause ->
                            logError(
                                "Root cause: ${cause::class.java.simpleName} - ${cause.message}",
                                cause
                            )
                        }
                        logError("Export result: $exportResult")
                        processingError = exportException
                        latch.countDown()
                    }
                })

            val transformer = transformerBuilder.build()

            // Create EditedMediaItem with effects
            val editedMediaItemBuilder = EditedMediaItem.Builder(mediaItem)

            // Apply effects if any
            if (videoEffects.isNotEmpty()) {
                logVerbose("Applying ${videoEffects.size} video effects to EditedMediaItem")
                val effects = Effects(
                    /* audioProcessors = */ emptyList(),
                    /* videoEffects = */ videoEffects
                )
                editedMediaItemBuilder.setEffects(effects)
            }

            val editedMediaItem = editedMediaItemBuilder.build()
            @Suppress("DEPRECATION")
            val sequence = EditedMediaItemSequence.Builder(listOf(editedMediaItem)).build()
            val composition = Composition.Builder(listOf(sequence)).build()

            // Start export
            logVerbose("Starting export...")
            transformer.start(composition, outputPath)

            // Monitor progress
            val progressJob = launch {
                while (latch.count > 0) {
                    val progressHolder = ProgressHolder()
                    val progressState = transformer.getProgress(progressHolder)

                    when (progressState) {
                        Transformer.PROGRESS_STATE_NOT_STARTED -> {
                            logProgress("Progress: Not started")
                        }
                        Transformer.PROGRESS_STATE_WAITING_FOR_AVAILABILITY -> {
                            logProgress("Progress: Waiting for availability")
                        }
                        Transformer.PROGRESS_STATE_AVAILABLE -> {
                            val progress = progressHolder.progress / 100f
                            logProgress("Progress: ${(progress * 100).roundToInt()}%")
                            onProgress?.invoke(progress)
                        }
                        Transformer.PROGRESS_STATE_UNAVAILABLE -> {
                            logProgress("Progress: Unavailable")
                        }
                    }

                    delay(100)
                }
            }

            // Wait for completion
            withContext(Dispatchers.IO) {
                latch.await()
            }
            progressJob.cancel()

            // Check for errors
            processingError?.let { throw it }

            val processingTime = System.currentTimeMillis() - startTime
            logVerbose("Processing completed in ${processingTime}ms")

            // Verify output file exists
            val outputFile = File(outputPath)
            if (!outputFile.exists()) {
                throw VideoProcessingException("Output file was not created")
            }

            logVerbose("Output file size: ${outputFile.length()} bytes")

            ProcessingResult(
                outputPath = outputPath,
                processingTimeMs = processingTime,
                isReEncoded = hasVideoEffects || (trimStartMs != null),
                method = "Media3 Transformer"
            )

        } catch (e: Exception) {
            if (e is ExportException) {
                logError(
                    "Media3 transformer failed (code=${e.errorCode}, type=${e::class.java.simpleName})",
                    e
                )
                e.cause?.let { cause ->
                    logError(
                        "Media3 transformer root cause: ${cause::class.java.simpleName} - ${cause.message}",
                        cause
                    )
                }
            } else {
                logError("Failed to process video", e)
            }
            throw VideoProcessingException("Video processing failed: ${e.message}", e)
        }
    }

    /**
     * Dedicated trim operation for optimal performance
     */
    suspend fun trimVideo(
        inputPath: String,
        outputPath: String,
        startTimeMs: Long,
        endTimeMs: Long,
        onProgress: ((Float) -> Unit)? = null
    ): ProcessingResult {
        return processVideo(
            inputPath = inputPath,
            outputPath = outputPath,
            trimStartMs = startTimeMs,
            trimEndMs = endTimeMs,
            onProgress = onProgress
        )
    }

    /**
     * Dedicated rotate operation
     */
    suspend fun rotateVideo(
        inputPath: String,
        outputPath: String,
        degrees: Int,
        onProgress: ((Float) -> Unit)? = null
    ): ProcessingResult {
        return processVideo(
            inputPath = inputPath,
            outputPath = outputPath,
            rotateDegrees = degrees,
            onProgress = onProgress
        )
    }

    /**
     * Dedicated crop operation
     */
    suspend fun cropVideo(
        inputPath: String,
        outputPath: String,
        cropX: Int,
        cropY: Int,
        cropWidth: Int,
        cropHeight: Int,
        onProgress: ((Float) -> Unit)? = null
    ): ProcessingResult {
        return processVideo(
            inputPath = inputPath,
            outputPath = outputPath,
            cropX = cropX,
            cropY = cropY,
            cropWidth = cropWidth,
            cropHeight = cropHeight,
            onProgress = onProgress
        )
    }

    /**
     * Get video information
     */
    private fun getVideoInfo(videoPath: String): VideoInfo {
        val retriever = android.media.MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)

            VideoInfo(
                width = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                )?.toIntOrNull() ?: 0,
                height = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                )?.toIntOrNull() ?: 0,
                rotation = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                )?.toIntOrNull() ?: 0,
                duration = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L,
                bitrate = retriever.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE
                )?.toLongOrNull() ?: 0L
            )
        } finally {
            retriever.release()
        }
    }

    // Logging helpers
    private fun logVerbose(message: String) {
        if (LOG_VERBOSE) Log.d(TAG, message)
    }

    private fun logProgress(message: String) {
        if (LOG_PROGRESS) Log.i(TAG, message)
    }

    private fun logError(message: String, throwable: Throwable? = null) {
        if (LOG_ERRORS) {
            if (throwable != null) {
                Log.e(TAG, message, throwable)
            } else {
                Log.e(TAG, message)
            }
        }
    }
}

/**
 * Video information data class
 */
private data class VideoInfo(
    val width: Int,
    val height: Int,
    val rotation: Int,
    val duration: Long,
    val bitrate: Long
)

/**
 * Result of video processing operation
 */
data class ProcessingResult(
    val outputPath: String,
    val processingTimeMs: Long,
    val isReEncoded: Boolean,
    val method: String
)

/**
 * Custom exception for video processing errors
 */
class VideoProcessingException(message: String, cause: Throwable? = null) : Exception(message, cause)
