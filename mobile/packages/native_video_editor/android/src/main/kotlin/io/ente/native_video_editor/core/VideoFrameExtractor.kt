package io.ente.native_video_editor.core

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.inspector.frame.FrameExtractor
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutionException
import kotlin.coroutines.coroutineContext

@UnstableApi
class VideoFrameExtractor(
    private val context: Context,
    private val metadataReader: VideoMetadataReader
) {
    private val permits = Semaphore(2)

    suspend fun extract(request: VideoFrameRequest): VideoFrameExtractionResult {
        val writtenFiles = mutableListOf<File>()
        return try {
            withContext(Dispatchers.IO) {
                val inputFile = File(request.inputPath).canonicalFile
                val outputFiles = request.outputPaths.map { File(it).canonicalFile }
                require(inputFile.isFile && outputFiles.none { it == inputFile }) {
                    "Input must be a video file and outputs must use different paths"
                }

                permits.withPermit {
                    extractWithRetriever(request, outputFiles, writtenFiles)
                }
            }
        } catch (error: Throwable) {
            writtenFiles.forEach(File::delete)
            throw error
        }
    }

    private suspend fun extractWithRetriever(
        request: VideoFrameRequest,
        outputFiles: List<File>,
        writtenFiles: MutableList<File>
    ): VideoFrameExtractionResult {
        val retriever = MediaMetadataRetriever()
        var fallbackExtractor: FrameExtractor? = null
        try {
            retriever.setDataSource(request.inputPath)
            val videoInfo = metadataReader.read(retriever)
            val targetSize = boundedVideoSize(
                videoInfo.displayWidth,
                videoInfo.displayHeight,
                request.maxWidth,
                request.maxHeight
            )
            val precise = request.policy == VideoFramePolicy.PRECISE
            val option = if (precise) {
                MediaMetadataRetriever.OPTION_CLOSEST
            } else {
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            }
            val frames = ArrayList<VideoFrameResult>(request.positionsMs.size)

            request.positionsMs.forEachIndexed { index, requestedPositionMs ->
                coroutineContext.ensureActive()
                val positionMs = clampFramePositionMs(requestedPositionMs, videoInfo.durationMs)
                val frame = try {
                    extractScaledFrame(
                        retriever,
                        positionMs * 1_000,
                        option,
                        targetSize.width,
                        targetSize.height
                    )
                } catch (error: RuntimeException) {
                    Log.w(TAG, "Platform frame decoder failed at ${positionMs}ms", error)
                    null
                } ?: run {
                    Log.w(TAG, "Platform decoder returned no frame at ${positionMs}ms; using Media3")
                    val extractor = fallbackExtractor ?: createFallbackExtractor(
                        request.inputPath,
                        targetSize.height,
                        precise
                    ).also { fallbackExtractor = it }
                    extractFallbackFrame(extractor, positionMs)
                }
                coroutineContext.ensureActive()

                val outputFile = outputFiles[index]
                outputFile.parentFile?.mkdirs()
                try {
                    try {
                        FileOutputStream(outputFile, false).use { stream ->
                            check(frame.compress(Bitmap.CompressFormat.JPEG, request.quality, stream)) {
                                "JPEG encoder rejected the frame"
                            }
                        }
                    } catch (error: Exception) {
                        outputFile.delete()
                        throw error
                    }
                    writtenFiles.add(outputFile)
                    frames.add(
                        VideoFrameResult(request.outputPaths[index], frame.width, frame.height)
                    )
                } finally {
                    frame.recycle()
                }
            }

            return VideoFrameExtractionResult(videoInfo, frames)
        } finally {
            retriever.release()
            fallbackExtractor?.let { extractor ->
                withContext(NonCancellable + Dispatchers.Main) {
                    extractor.close()
                }
            }
        }
    }

    private fun extractScaledFrame(
        retriever: MediaMetadataRetriever,
        positionUs: Long,
        option: Int,
        targetWidth: Int,
        targetHeight: Int
    ): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return retriever.getScaledFrameAtTime(
                positionUs,
                option,
                targetWidth,
                targetHeight
            )
        }

        val source = retriever.getFrameAtTime(positionUs, option) ?: return null
        if (source.width <= targetWidth && source.height <= targetHeight) return source

        val size = boundedVideoSize(source.width, source.height, targetWidth, targetHeight)
        val scaled = Bitmap.createScaledBitmap(source, size.width, size.height, true)
        if (scaled !== source) source.recycle()
        return scaled
    }

    private suspend fun createFallbackExtractor(
        inputPath: String,
        targetHeight: Int,
        precise: Boolean
    ): FrameExtractor = withContext(Dispatchers.Main) {
        FrameExtractor.Builder(
            context,
            MediaItem.fromUri(Uri.fromFile(File(inputPath)))
        )
            .setEffects(listOf(Presentation.createForHeight(targetHeight)))
            .setSeekParameters(if (precise) SeekParameters.EXACT else SeekParameters.CLOSEST_SYNC)
            .build()
    }

    private suspend fun extractFallbackFrame(
        extractor: FrameExtractor,
        positionMs: Long
    ): Bitmap {
        val future = withContext(Dispatchers.Main) { extractor.getFrame(positionMs) }
        return future.awaitResult().bitmap
    }

    private suspend fun <T> ListenableFuture<T>.awaitResult(): T =
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { cancel(true) }
            addListener(
                {
                    try {
                        continuation.resumeWith(Result.success(get()))
                    } catch (error: ExecutionException) {
                        continuation.resumeWith(Result.failure(error.cause ?: error))
                    } catch (error: Exception) {
                        continuation.resumeWith(Result.failure(error))
                    }
                },
                MoreExecutors.directExecutor()
            )
        }

    private companion object {
        const val TAG = "VideoFrameExtractor"
    }
}
