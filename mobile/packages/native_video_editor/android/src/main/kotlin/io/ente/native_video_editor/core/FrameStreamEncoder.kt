package io.ente.native_video_editor.core

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CancellationException
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal data class FrameStreamRequest(
    val outputPath: String,
    val width: Int,
    val height: Int,
    val frameRate: Int,
    val bitrate: Int
) {
    init {
        require(outputPath.isNotBlank()) { "Missing output path" }
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
            "Frame size must be positive and even"
        }
        require(frameRate in 1..60) { "Frame rate must be between 1 and 60" }
        require(bitrate > 0) { "Bitrate must be positive" }
    }
}

internal class FrameStreamEncoder(private val request: FrameStreamRequest) {
    private val width = request.width
    private val height = request.height
    private val gl: ExecutorService =
        Executors.newSingleThreadExecutor { Thread(it, "FrameStreamGl") }
    private val codec: MediaCodec
    private val inputSurface: Surface
    private val renderer: FrameRenderer
    private val muxer: MediaMuxer
    private val drain: Thread
    private val input = Any()
    private var frameCount = 0L
    private var track = -1
    private var released = false

    @Volatile
    private var failure: Throwable? = null

    @Volatile
    private var stopped = false

    init {
        File(request.outputPath).delete()
        val info = hardwareEncoder()
            ?: throw IllegalStateException("No hardware H.264 encoder supports ${width}x$height")
        codec = MediaCodec.createByCodecName(info.name)
        var surface: Surface? = null
        var drawing: FrameRenderer? = null
        try {
            configure(info)
            val created = codec.createInputSurface()
            surface = created
            codec.start()
            drawing = onGl { FrameRenderer(created, width, height) }
            muxer = MediaMuxer(request.outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            renderer = drawing
            inputSurface = created
        } catch (error: Throwable) {
            drawing?.let { runCatching { onGl { it.release() } } }
            gl.shutdown()
            surface?.release()
            runCatching { codec.stop() }
            codec.release()
            throw error
        }
        drain = Thread(::drainOutput, "FrameStreamEncoder").apply { start() }
    }

    fun encode(rgba: ByteBuffer) {
        synchronized(input) {
            throwIfFailed()
            require(rgba.remaining() == width * height * 4) { "Video frame has the wrong size" }
            val presentationNanos = frameCount * 1_000_000_000L / request.frameRate
            onGl { renderer.draw(rgba, presentationNanos) }
            frameCount++
        }
    }

    fun finish(): String {
        try {
            synchronized(input) {
                throwIfFailed()
                check(frameCount > 0) { "The video frame stream has no frames" }
                codec.signalEndOfInputStream()
            }
            drain.join()
            throwIfFailed()
            muxer.stop()
            synchronized(input) { release() }
            return request.outputPath
        } catch (error: Throwable) {
            cancel()
            throw error
        }
    }

    fun cancel() {
        if (failure == null) failure = CancellationException("Export cancelled")
        synchronized(input) {
            stopped = true
            drain.join()
            release()
        }
        File(request.outputPath).delete()
    }

    private fun hardwareEncoder(): MediaCodecInfo? =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.firstOrNull { info ->
            info.isEncoder &&
                isHardware(info) &&
                info.supportedTypes.any { it.equals(MIME, ignoreCase = true) } &&
                info.getCapabilitiesForType(MIME).let { capabilities ->
                    capabilities.colorFormats.contains(SURFACE_INPUT) &&
                        capabilities.videoCapabilities.areSizeAndRateSupported(
                            width,
                            height,
                            request.frameRate.toDouble()
                        )
                }
        }

    private fun isHardware(info: MediaCodecInfo): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            info.isHardwareAccelerated
        } else {
            SOFTWARE_PREFIXES.none { info.name.startsWith(it) }
        }

    private fun configure(info: MediaCodecInfo) {
        val high = info.getCapabilitiesForType(MIME).profileLevels
            .filter { it.profile == MediaCodecInfo.CodecProfileLevel.AVCProfileHigh }
            .maxByOrNull { it.level }
        if (high != null) {
            try {
                codec.configure(
                    videoFormat().apply {
                        setInteger(MediaFormat.KEY_PROFILE, high.profile)
                        setInteger(MediaFormat.KEY_LEVEL, high.level)
                    },
                    null,
                    null,
                    MediaCodec.CONFIGURE_FLAG_ENCODE
                )
                return
            } catch (_: IllegalArgumentException) {
                codec.reset()
            } catch (_: MediaCodec.CodecException) {
                codec.reset()
            }
        }
        codec.configure(videoFormat(), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    }

    private fun videoFormat(): MediaFormat =
        MediaFormat.createVideoFormat(MIME, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, SURFACE_INPUT)
            setInteger(MediaFormat.KEY_BIT_RATE, request.bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, request.frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
            }
        }

    private fun <T> onGl(task: () -> T): T =
        try {
            gl.submit(task).get()
        } catch (error: ExecutionException) {
            throw error.cause ?: error
        }

    private fun drainOutput() {
        val info = MediaCodec.BufferInfo()
        try {
            while (!stopped) {
                val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                } else if (index >= 0) {
                    val buffer = codec.getOutputBuffer(index)
                    val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (buffer != null && info.size > 0 && !isConfig) {
                        check(track >= 0) { "Encoder output arrived before its format" }
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        } catch (error: Throwable) {
            if (failure == null) failure = error
        }
    }

    private fun throwIfFailed() {
        failure?.let { throw it }
    }

    private fun release() {
        if (released) return
        released = true
        runCatching { onGl { renderer.release() } }
        gl.shutdown()
        inputSurface.release()
        runCatching { codec.stop() }
        codec.release()
        runCatching { muxer.release() }
    }

    private companion object {
        const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        const val SURFACE_INPUT = MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
        const val TIMEOUT_US = 10_000L
        val SOFTWARE_PREFIXES = listOf("OMX.google.", "c2.android.")
    }
}
