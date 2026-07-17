package io.ente.ensu.chat

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import io.ente.ensu.bindings.LlmException
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.bindings.TranscriptionException
import io.ente.ensu.bindings.uniffiEnsureInitialized
import io.ente.ensu.llm.ModelDownloader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlin.coroutines.coroutineContext

internal sealed interface VoiceInputState {
    data object Idle : VoiceInputState
    data object Recording : VoiceInputState
    data class Downloading(val percent: Int?) : VoiceInputState
    data object Transcribing : VoiceInputState
    data class Error(val message: String) : VoiceInputState
}

internal val VoiceInputState.isRecording: Boolean
    get() = this is VoiceInputState.Recording

internal val VoiceInputState.isWorking: Boolean
    get() = this is VoiceInputState.Recording ||
        this is VoiceInputState.Downloading ||
        this is VoiceInputState.Transcribing

internal val VoiceInputState.blocksSend: Boolean
    get() = this is VoiceInputState.Recording ||
        this is VoiceInputState.Transcribing

internal fun VoiceInputState.statusText(): String? = when (this) {
    VoiceInputState.Idle -> null
    VoiceInputState.Recording -> "Listening..."
    is VoiceInputState.Downloading -> {
        val suffix = percent?.let { " ($it%)" } ?: ""
        "Downloading voice model...$suffix"
    }
    VoiceInputState.Transcribing -> null
    is VoiceInputState.Error -> message
}

@Composable
internal fun rememberVoiceTranscriptionController(
    modelDownloader: ModelDownloader,
    transcriber: Transcriber,
    onTranscript: (String) -> Unit
): VoiceTranscriptionController {
    val lifecycleOwner = LocalLifecycleOwner.current
    val controller = remember(transcriber) {
        VoiceTranscriptionController(modelDownloader, transcriber, onTranscript)
    }
    DisposableEffect(controller, lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) {
                controller.cancelActiveVoiceInput()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }
    DisposableEffect(controller) {
        onDispose { controller.dispose() }
    }
    return controller
}

internal class VoiceTranscriptionController(
    private val modelDownloader: ModelDownloader,
    private val transcriber: Transcriber,
    private val onTranscript: (String) -> Unit
) {
    private val modelTargets = listOf(
        modelDownloader.transcriptionModelTarget,
        modelDownloader.voiceActivityModelTarget
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val bufferLock = Any()

    private var audioRecord: AudioRecord? = null
    private var preparingRecordingJob: Job? = null
    private var recordingJob: Job? = null
    private var transcriptionPreloadJob: Job? = null
    private var transientErrorJob: Job? = null
    private var recordedPcm = ByteArrayOutputStream()
    private var recordingSampleRate = preferredSampleRate

    var state: VoiceInputState by mutableStateOf(VoiceInputState.Idle)
        private set

    fun onPermissionDenied() {
        state = VoiceInputState.Error("Microphone permission is required for voice input.")
    }

    @SuppressLint("MissingPermission")
    fun startRecording(canStartRecording: () -> Boolean = { true }) {
        transientErrorJob?.cancel()
        if (state.isWorking || preparingRecordingJob?.isActive == true) {
            return
        }

        preparingRecordingJob = scope.launch {
            try {
                ensureTranscriptionModelDownloaded()
                if (!isActive || !canStartRecording()) {
                    if (state is VoiceInputState.Downloading) {
                        state = VoiceInputState.Idle
                    }
                    return@launch
                }
                beginRecording()
                preloadTranscriptionModel()
            } catch (error: CancellationException) {
                throw error
            } catch (error: UnsatisfiedLinkError) {
                Log.w(TAG, "Voice transcription is not available on this device", error)
                state = VoiceInputState.Error("Voice transcription is not available on this device.")
            } catch (error: TranscriptionException) {
                Log.w(TAG, "Voice model preparation failed: ${error.message}", error)
                state = VoiceInputState.Error(transcriptionErrorMessage(error))
            } catch (error: LlmException) {
                if (error is LlmException.Cancelled) {
                    state = VoiceInputState.Idle
                    return@launch
                }
                Log.w(TAG, "Voice model download failed: ${error.message}", error)
                state = VoiceInputState.Error(downloadErrorMessage())
            } catch (error: Throwable) {
                Log.w(
                    TAG,
                    "Voice model preparation failed: ${error.javaClass.simpleName}: ${error.message}",
                    error
                )
                state = VoiceInputState.Error("Could not transcribe voice input.")
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun beginRecording() {
        if (state is VoiceInputState.Recording || state is VoiceInputState.Transcribing) {
            return
        }

        synchronized(bufferLock) {
            recordedPcm = ByteArrayOutputStream()
        }
        recordingSampleRate = preferredSampleRate
        state = VoiceInputState.Recording

        recordingJob = scope.launch(Dispatchers.IO) {
            var recorder: AudioRecord? = null
            try {
                val activeRecorder = createRecorder(recordingSampleRate)
                recorder = activeRecorder
                audioRecord = activeRecorder
                recordingSampleRate = activeRecorder.sampleRate.takeIf { it > 0 } ?: preferredSampleRate
                activeRecorder.startRecording()
                val buffer = ByteArray(readBufferSize(recordingSampleRate))
                while (coroutineContext.isActive) {
                    val read = activeRecorder.read(buffer, 0, buffer.size)
                    when {
                        read > 0 -> synchronized(bufferLock) {
                            recordedPcm.write(buffer, 0, read)
                        }
                        read < 0 -> throw IOException("Audio recorder failed with code $read")
                    }
                }
            } catch (error: Throwable) {
                if (error is CancellationException) {
                    throw error
                }
                Log.w(TAG, "Could not record microphone audio", error)
                withContext(Dispatchers.Main.immediate) {
                    if (state is VoiceInputState.Recording) {
                        state = VoiceInputState.Error("Could not record microphone audio.")
                    }
                }
            } finally {
                runCatching {
                    if (recorder?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        recorder.stop()
                    }
                }
                recorder?.release()
                if (audioRecord === recorder) {
                    audioRecord = null
                }
            }
        }
    }

    fun stopAndTranscribe() {
        if (state !is VoiceInputState.Recording) {
            return
        }

        state = VoiceInputState.Transcribing
        preparingRecordingJob?.cancel()
        preparingRecordingJob = null
        scope.launch {
            recordingJob?.cancelAndJoin()
            recordingJob = null

            val pcm = synchronized(bufferLock) { recordedPcm.toByteArray() }
            if (pcm.size < minimumRecordingBytes(recordingSampleRate)) {
                showTransientError("No speech captured.")
                return@launch
            }

            transcribeRecording(pcm, recordingSampleRate)
        }
    }

    fun cancelActiveVoiceInput() {
        val wasPreparingRecording = preparingRecordingJob?.isActive == true
        preparingRecordingJob?.cancel()
        preparingRecordingJob = null

        if (state !is VoiceInputState.Recording) {
            if (wasPreparingRecording && state is VoiceInputState.Downloading) {
                state = VoiceInputState.Idle
            }
            return
        }

        state = VoiceInputState.Idle
        recordingJob?.cancel()
        recordingJob = null
        stopActiveRecorder()
        synchronized(bufferLock) {
            recordedPcm.reset()
        }
    }

    fun dispose() {
        transientErrorJob?.cancel()
        preparingRecordingJob?.cancel()
        scope.cancel()
        runCatching {
            audioRecord?.release()
        }
        audioRecord = null
    }

    private suspend fun transcribeRecording(pcm: ByteArray, sampleRate: Int) {
        try {
            ensureTranscriptionModelDownloaded()
            awaitTranscriptionModelPreload()
            val transcript = withContext(Dispatchers.IO) {
                uniffiEnsureInitialized()

                withContext(Dispatchers.Main.immediate) {
                    state = VoiceInputState.Transcribing
                }
                transcriber.transcribe(
                    sampleRate.toUInt(),
                    pcm
                )
            }.trim()

            if (transcript.isBlank()) {
                showTransientError("No speech detected.")
            } else {
                onTranscript(transcript)
                state = VoiceInputState.Idle
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: UnsatisfiedLinkError) {
            Log.w(TAG, "Voice transcription is not available on this device", error)
            state = VoiceInputState.Error("Voice transcription is not available on this device.")
        } catch (error: TranscriptionException) {
            Log.w(TAG, "Voice transcription failed: ${error.message}", error)
            state = VoiceInputState.Error(transcriptionErrorMessage(error))
        } catch (error: LlmException) {
            if (error is LlmException.Cancelled) {
                state = VoiceInputState.Idle
                return
            }
            Log.w(TAG, "Voice model download failed: ${error.message}", error)
            state = VoiceInputState.Error(downloadErrorMessage())
        } catch (error: Throwable) {
            Log.w(
                TAG,
                "Voice transcription failed: ${error.javaClass.simpleName}: ${error.message}",
                error
            )
            state = VoiceInputState.Error("Could not transcribe voice input.")
        }
    }

    private fun preloadTranscriptionModel() {
        transcriptionPreloadJob?.cancel()
        transcriptionPreloadJob = scope.launch(Dispatchers.IO) {
            try {
                uniffiEnsureInitialized()
                transcriber.loadModel()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                Log.w(TAG, "Voice model preload failed", error)
            }
        }
    }

    private suspend fun awaitTranscriptionModelPreload() {
        val preloadJob = transcriptionPreloadJob ?: return
        try {
            preloadJob.join()
        } finally {
            if (transcriptionPreloadJob == preloadJob) {
                transcriptionPreloadJob = null
            }
        }
    }

    private suspend fun ensureTranscriptionModelDownloaded() {
        val activeJob = coroutineContext[Job]
        uniffiEnsureInitialized()

        if (withContext(Dispatchers.IO) { modelTargets.all { modelDownloader.isDownloaded(it) } }) {
            return
        }

        setStateIfJobActive(activeJob, VoiceInputState.Downloading(null))
        modelDownloader.download(modelTargets) { progress ->
            postStateIfJobActive(activeJob, VoiceInputState.Downloading(progress.percent?.coerceIn(0, 100)))
        }
    }

    private suspend fun setStateIfJobActive(activeJob: Job?, nextState: VoiceInputState) {
        if (activeJob?.isActive == false) {
            return
        }
        withContext(Dispatchers.Main.immediate) {
            if (activeJob?.isActive != false) {
                state = nextState
            }
        }
    }

    private fun postStateIfJobActive(activeJob: Job?, nextState: VoiceInputState) {
        if (activeJob?.isActive == false) {
            return
        }
        scope.launch(Dispatchers.Main.immediate) {
            if (activeJob?.isActive != false) {
                state = nextState
            }
        }
    }

    private fun stopActiveRecorder() {
        val recorder = audioRecord ?: return
        runCatching {
            if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                recorder.stop()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun createRecorder(sampleRate: Int): AudioRecord {
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufferSize <= 0) {
            throw IOException("Audio recorder buffer unavailable")
        }

        return AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minBufferSize * 2)
            .build()
            .also { recorder ->
                if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                    recorder.release()
                    throw IOException("Audio recorder failed to initialize")
                }
            }
    }

    private fun readBufferSize(sampleRate: Int): Int {
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        return maxOf(minBufferSize, 4096)
    }

    private fun minimumRecordingBytes(sampleRate: Int): Int = sampleRate / 4 * bytesPerSample

    private fun downloadErrorMessage(): String =
        "Voice model download failed. Check your connection and try again."

    private fun transcriptionErrorMessage(error: TranscriptionException): String = when (error) {
        is TranscriptionException.NotDownloaded,
        is TranscriptionException.VadNotDownloaded,
        is TranscriptionException.Transcribe -> "Voice model could not be loaded."
        is TranscriptionException.InvalidAudio -> "Could not detect speech in this recording."
        is TranscriptionException.StorageFull ->
            "Not enough storage space. Please free up space and try again."
        is TranscriptionException.Io -> "Could not transcribe voice input."
    }

    private fun showTransientError(message: String) {
        val errorState = VoiceInputState.Error(message)
        transientErrorJob?.cancel()
        state = errorState
        transientErrorJob = scope.launch {
            delay(transientErrorMillis)
            if (state == errorState) {
                state = VoiceInputState.Idle
            }
        }
    }

    private companion object {
        const val TAG = "VoiceInput"
        const val preferredSampleRate = 16_000
        const val bytesPerSample = 2
        const val transientErrorMillis = 10_000L
    }
}
