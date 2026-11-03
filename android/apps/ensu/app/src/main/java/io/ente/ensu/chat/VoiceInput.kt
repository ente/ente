package io.ente.ensu.chat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.AssetDownloadException
import io.ente.ensu.bindings.DictationException
import io.ente.ensu.bindings.DictationFeedResult
import io.ente.ensu.bindings.DictationInsertion
import io.ente.ensu.bindings.DictationPhase
import io.ente.ensu.bindings.DictationSession
import io.ente.ensu.bindings.DictationSnapshot
import io.ente.ensu.bindings.DictationStopReason
import io.ente.ensu.bindings.DictationStream
import io.ente.ensu.bindings.DictationStreamCallback
import io.ente.ensu.bindings.supportsLiveVoice
import io.ente.ensu.bindings.transcriptionModelAsset
import io.ente.ensu.bindings.voiceActivityModelAsset
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.llm.ModelMemoryUnavailable
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.sqrt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal enum class VoiceInputFailure(val message: String) {
    Permission("Microphone permission is required. Enable it in Settings."),
    NoSpeech("No speech detected. Try again."),
    Download("Voice model download failed. Check your connection and try again."),
    ModelUnavailable("Voice model could not be loaded. Try again."),
    StorageFull("Not enough storage space. Free up space and try again."),
    FileAccess("Could not read or save voice data. Check storage and try again."),
    MemoryUnavailable("Not enough free memory. Close other apps and try again."),
    MicrophoneUnavailable("Could not start the microphone. Tap the microphone to try again."),
    Interrupted("Voice input was interrupted. Review the available text and try again."),
    Incomplete("Some words may be missing. Review the text."),
    ProcessingFailed("Could not transcribe voice input. Review the available text and try again."),
}

internal fun voiceInputFailure(error: Exception): VoiceInputFailure =
    when (error) {
        is ModelMemoryUnavailable -> VoiceInputFailure.MemoryUnavailable
        is AssetDownloadException.StorageFull,
        is DictationException.StorageFull -> VoiceInputFailure.StorageFull
        is AssetDownloadException.Cancelled,
        is DictationException.Cancelled,
        is DictationException.InvalidAudio -> VoiceInputFailure.Interrupted
        is AssetDownloadException.Io,
        is DictationException.Io,
        is IOException -> VoiceInputFailure.FileAccess
        is AssetDownloadException -> VoiceInputFailure.Download
        is DictationException.NotDownloaded,
        is DictationException.VadNotDownloaded -> VoiceInputFailure.ModelUnavailable
        else -> VoiceInputFailure.ProcessingFailed
    }

internal sealed interface VoiceInputState {
    data object Idle : VoiceInputState

    data object Preparing : VoiceInputState

    data object Recording : VoiceInputState

    data class Downloading(val percent: Int?, val queued: Boolean = true) : VoiceInputState

    data object Transcribing : VoiceInputState

    data class Error(val reason: VoiceInputFailure) : VoiceInputState
}

internal val VoiceInputState.isRecording: Boolean
    get() = this is VoiceInputState.Recording

internal class VoiceTranscriptionController(
    context: Context,
    private val assetStore: AssetStore,
    private val llmProvider: LlmProvider,
    private val logRepository: FileLogRepository,
    private val onVoiceInputJob: (Job) -> Unit,
    private val onInsert: (DictationInsertion, String) -> Boolean,
) {
    private fun microphoneFailure(error: Exception): VoiceInputFailure =
        if (error is SecurityException) VoiceInputFailure.Permission
        else VoiceInputFailure.MicrophoneUnavailable

    private fun logFailure(error: Exception) =
        logRepository.log(
            LogLevel.Error,
            "Voice input failed",
            tag = "EnsuVoice",
            throwable = error,
        )

    private val applicationContext = context.applicationContext
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val usesLiveDictation =
        supportsLiveVoice(
            AndroidDeviceCapabilityProvider(context)
                .chatCapability()
                .totalMemoryBytes
                ?.takeIf { it > 0 }
                ?.toULong()
        )
    private val modelAssets =
        listOf(
            transcriptionModelAsset(),
            voiceActivityModelAsset(),
        )
    private var session: DictationSession? = null
    private var stream: DictationStream? = null
    private var capture: LiveMicrophone? = null
    private var work: Job? = null
    private var finishingNoticeJob: Job? = null
    private var transientErrorJob: Job? = null
    private var attemptFinished = false
    private var insertion: DictationInsertion? = null
    private var insertionFactory: (() -> DictationInsertion?)? = null
    private var foreground = true
    private var generation = 0L
    val sessionVersion: Long
        get() = generation

    private var initialRecordPending = false
    private var awaitingPermission = false
    private var startOnForeground = false

    var active by mutableStateOf(false)
        private set

    var state: VoiceInputState by mutableStateOf(VoiceInputState.Idle)
        private set

    var isFinishingSlow by mutableStateOf(false)
        private set

    var snapshot: DictationSnapshot? by mutableStateOf(null)
        private set

    private var failure: VoiceInputFailure? = null

    var audioLevels: List<Float> by mutableStateOf(List(24) { 0f })
        private set

    var composerCaret: Int? by mutableStateOf(null)

    var hasActiveWork by mutableStateOf(false)
        private set

    val canOpen: Boolean
        get() = !active && !hasActiveWork

    val blocksComposer: Boolean
        get() = active && state != VoiceInputState.Idle && state !is VoiceInputState.Downloading

    fun open(insertionFactory: () -> DictationInsertion?) {
        if (!canOpen) return
        transientErrorJob?.cancel()
        generation++
        initialRecordPending = true
        attemptFinished = false
        isFinishingSlow = false
        this.insertionFactory = insertionFactory
        session = DictationSession(live = usesLiveDictation)
        snapshot = session?.snapshot()
        failure = null
        audioLevels = List(24) { 0f }
        active = true
        state = VoiceInputState.Idle
    }

    fun composerPreview(original: String): io.ente.ensu.bindings.DictationInsertionResult? {
        val value = snapshot ?: return null
        if (!blocksComposer) return null
        return runCatching { insertion?.preview(original, value.text + value.hypothesis) }
            .getOrNull()
    }

    fun takeInitialRecord(): Boolean = initialRecordPending.also { initialRecordPending = false }

    fun permissionRequested() {
        awaitingPermission = true
    }

    fun permissionResult(granted: Boolean) {
        awaitingPermission = false
        if (granted) {
            if (foreground) record() else startOnForeground = true
        } else {
            discard()
            state = VoiceInputState.Error(VoiceInputFailure.Permission)
        }
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (active) {
            if (startOnForeground) {
                startOnForeground = false
                record()
            } else session?.let { refresh(it, generation) }
        } else if (
            !awaitingPermission && !startOnForeground && state !is VoiceInputState.Downloading
        )
            interrupt()
    }

    fun record() {
        val owner = session ?: return
        if (!active || !foreground || hasActiveWork || attemptFinished) return
        failure = null
        state = VoiceInputState.Downloading(null)
        val token = generation
        hasActiveWork = true
        work =
            scope
                .launch {
                    var ownedCapture: LiveMicrophone? = null
                    var ownedStream: DictationStream? = null
                    var attemptError: Exception? = null
                    var completed = false
                    try {
                        if (
                            !withContext(Dispatchers.IO) {
                                modelAssets.all { assetStore.isDownloaded(it) }
                            }
                        ) {
                            assetStore.download(modelAssets) { progress ->
                                scope.launch {
                                    if (token == generation && state is VoiceInputState.Downloading)
                                        state =
                                            VoiceInputState.Downloading(
                                                progress.totalBytes?.let {
                                                    progress.percentage.toInt()
                                                },
                                                progress.queued,
                                            )
                                }
                            }
                        }
                        if (token != generation) return@launch
                        if (!foreground) {
                            discard()
                            return@launch
                        }
                        insertion = insertionFactory?.invoke()
                        insertionFactory = null
                        if (insertion == null) {
                            discard()
                            return@launch
                        }
                        state = VoiceInputState.Preparing
                        val activeStream = DictationStream(owner, 16000u, 1u)
                        stream = activeStream
                        ownedStream = activeStream
                        val microphone =
                            LiveMicrophone(
                                activeStream,
                                audioManager,
                                onLevel = { level ->
                                    scope.launch {
                                        if (token == generation && state.isRecording)
                                            audioLevels = audioLevels.drop(1) + level
                                    }
                                },
                            ) { error ->
                                scope.launch {
                                    if (token == generation) {
                                        logFailure(error)
                                        interrupt()
                                    }
                                }
                            }
                        capture = microphone
                        ownedCapture = microphone
                        coroutineScope {
                            val hardwareReady =
                                async(Dispatchers.IO) {
                                    try {
                                        microphone.prepare(applicationContext)
                                    } catch (error: Exception) {
                                        withContext(Dispatchers.Main.immediate) {
                                            if (token == generation && failure == null)
                                                failure = microphoneFailure(error)
                                        }
                                        throw error
                                    }
                                }
                            val callback =
                                object : DictationStreamCallback {
                                    override fun onReady() {
                                        scope.launch {
                                            try {
                                                hardwareReady.await()
                                                val value = owner.snapshot()
                                                if (
                                                    token != generation ||
                                                        !foreground ||
                                                        !active ||
                                                        stream !== activeStream ||
                                                        !value.workerActive ||
                                                        value.phase != DictationPhase.LISTENING
                                                )
                                                    return@launch
                                                microphone.start(scope)
                                                state = VoiceInputState.Recording
                                                audioLevels = List(24) { 0f }
                                                failure = null
                                                refresh(owner, token)
                                            } catch (error: CancellationException) {
                                                throw error
                                            } catch (error: Exception) {
                                                if (token == generation) {
                                                    logFailure(error)
                                                    interrupt(microphoneFailure(error))
                                                }
                                            }
                                        }
                                    }

                                    override fun onChange() {
                                        scope.launch { refresh(owner, token) }
                                    }

                                    override fun onCaptureClosed() {
                                        microphone.stop()
                                        scope.launch {
                                            watchFinalization(owner, activeStream, token)
                                        }
                                    }
                                }
                            llmProvider.runLiveVoice(activeStream, callback)
                        }
                        completed = true
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: AssetDownloadException.Cancelled) {
                        attemptError = error
                    } catch (error: DictationException.Cancelled) {
                        attemptError = error
                    } catch (error: Exception) {
                        attemptError = error
                        logFailure(error)
                    } finally {
                        attemptError?.let { error ->
                            ownedStream?.let {
                                runCatching { it.abandon(DictationStopReason.FAILURE) }
                            }
                            if (token == generation && failure == null)
                                failure = voiceInputFailure(error)
                        }
                        if (!completed && token == generation && failure == null)
                            failure = VoiceInputFailure.Interrupted
                        withContext(NonCancellable) { ownedCapture?.stopAndDrain() }
                        hasActiveWork = false
                        if (token == generation) {
                            finishingNoticeJob?.cancel()
                            finishingNoticeJob = null
                            capture = null
                            stream = null
                            attemptFinished = true
                            refresh(owner, token)
                        }
                    }
                }
                .also(onVoiceInputJob)
    }

    private fun refresh(owner: DictationSession, token: Long) {
        if (token != generation || !active) return
        val value = owner.snapshot()
        snapshot = value
        if (!attemptFinished) {
            if (value.phase == DictationPhase.FINISHING) state = VoiceInputState.Transcribing
            return
        }
        if (!foreground) return
        val text = value.text + value.hypothesis
        val added = text.isNotBlank() && insertion?.let { onInsert(it, text) } == true
        val completedState =
            when {
                added && !value.incomplete -> VoiceInputState.Idle
                added && failure == VoiceInputFailure.ProcessingFailed ->
                    VoiceInputState.Error(VoiceInputFailure.Incomplete)
                text.isBlank() -> VoiceInputState.Error(failure ?: VoiceInputFailure.NoSpeech)
                else -> VoiceInputState.Error(failure ?: VoiceInputFailure.Interrupted)
            }
        active = false
        isFinishingSlow = false
        snapshot = null
        session = null
        insertion = null
        insertionFactory = null
        audioLevels = List(24) { 0f }
        state = completedState
        if (completedState == VoiceInputState.Error(VoiceInputFailure.NoSpeech)) {
            transientErrorJob = scope.launch {
                delay(10_000)
                if (token == generation && state == completedState) state = VoiceInputState.Idle
            }
        }
    }

    private fun watchFinalization(
        owner: DictationSession,
        finishingStream: DictationStream,
        token: Long,
    ) {
        if (
            token != generation ||
                !active ||
                stream !== finishingStream ||
                !owner.snapshot().workerActive ||
                finishingNoticeJob != null
        )
            return
        finishingNoticeJob = scope.launch {
            delay(10_000)
            if (
                token != generation ||
                    !active ||
                    stream !== finishingStream ||
                    !owner.snapshot().workerActive
            )
                return@launch
            isFinishingSlow = true
        }
    }

    fun stop() {
        val reason = DictationStopReason.DONE
        runCatching { session?.stop(reason) }
        snapshot = session?.snapshot()
        if (snapshot?.workerActive != true) return
        state = VoiceInputState.Transcribing
        audioLevels = List(24) { 0f }
        val active = stream
        val microphone = capture
        if (active != null) session?.let { watchFinalization(it, active, generation) }
        scope.launch {
            microphone?.stopAndDrain()
            runCatching { active?.stop(reason) }
        }
    }

    fun interrupt(reason: VoiceInputFailure = VoiceInputFailure.Interrupted) {
        if (!active || attemptFinished) return
        if (state is VoiceInputState.Downloading) {
            insertionFactory = null
            return
        }
        if (!hasActiveWork && stream == null) {
            discard()
            return
        }
        failure = reason
        state = VoiceInputState.Transcribing
        capture?.stop()
        runCatching { stream?.abandon(DictationStopReason.INTERRUPTION) }
        work?.cancel()
        finishingNoticeJob?.cancel()
        isFinishingSlow = false
    }

    fun discard(keepDownload: Boolean = false) {
        if (keepDownload && state is VoiceInputState.Downloading && hasActiveWork) {
            insertionFactory = null
            return
        }
        awaitingPermission = false
        startOnForeground = false
        generation++
        transientErrorJob?.cancel()
        transientErrorJob = null
        finishingNoticeJob?.cancel()
        finishingNoticeJob = null
        capture?.stop()
        runCatching { stream?.abandon(DictationStopReason.DISCARD) }
        work?.cancel()
        active = false
        isFinishingSlow = false
        state = VoiceInputState.Idle
        snapshot = null
        session = null
        insertion = null
        insertionFactory = null
        stream = null
        capture = null
    }

    fun dispose() {
        discard()
        scope.cancel()
    }
}

private class LiveMicrophone(
    private val stream: DictationStream,
    private val audioManager: AudioManager,
    private val onLevel: (Float) -> Unit,
    private val onInterrupted: (Exception) -> Unit,
) {
    private val stopped = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null
    private var readJob: Job? = null

    fun prepare(context: Context) {
        if (stopped.get() || recorder != null) return
        val minimum =
            AudioRecord.getMinBufferSize(
                16000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        if (minimum <= 0) throw IOException("Microphone format unavailable")
        if (
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Microphone permission is required")
        }
        val active =
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(16000)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(maxOf(minimum * 2, 6400))
                .build()
        if (active.state != AudioRecord.STATE_INITIALIZED) {
            active.release()
            throw IOException("Microphone unavailable")
        }
        recorder = active
    }

    fun start(scope: CoroutineScope) {
        if (stopped.get()) return
        val active = recorder ?: return
        try {
            active.startRecording()
            if (active.recordingState != AudioRecord.RECORDSTATE_RECORDING)
                throw IOException("Microphone did not start")
        } catch (error: Exception) {
            active.release()
            recorder = null
            throw error
        }
        var routedDevice = active.routedDevice?.id
        readJob =
            scope.launch(Dispatchers.IO) {
                val buffer = ByteBuffer.allocateDirect(3200).order(ByteOrder.LITTLE_ENDIAN)
                try {
                    captureMicrophoneAudio(
                        isStopped = stopped::get,
                        read = {
                            buffer.clear()
                            active.read(buffer, buffer.capacity(), AudioRecord.READ_BLOCKING)
                        },
                        isInterrupted = {
                            audioManager.isMicrophoneMute ||
                                (android.os.Build.VERSION.SDK_INT >= 29 &&
                                    active.activeRecordingConfiguration?.isClientSilenced ==
                                        true) ||
                                (routedDevice != null && active.routedDevice?.id != routedDevice)
                        },
                    ) { read ->
                        routedDevice = active.routedDevice?.id
                        buffer.position(0)
                        buffer.limit(read)
                        var energy = 0.0
                        for (index in 0 until read / 2) {
                            val sample = buffer.getShort(index * 2).toDouble() / 32768.0
                            energy += sample * sample
                        }
                        val rms = sqrt(energy / (read / 2).coerceAtLeast(1))
                        onLevel(
                            ((20 * log10(rms.coerceAtLeast(0.00001)) + 55) / 45)
                                .toFloat()
                                .coerceIn(0f, 1f)
                        )
                        stream.feed(buffer) == DictationFeedResult.ACCEPTED
                    }
                } catch (error: Exception) {
                    if (!stopped.get()) {
                        runCatching { stream.abandon(DictationStopReason.FAILURE) }
                        onInterrupted(error)
                    }
                } finally {
                    stop()
                    active.release()
                    recorder = null
                }
            }
    }

    suspend fun stopAndDrain() {
        stop()
        readJob?.join()
        recorder?.release()
        recorder = null
    }

    fun stop() {
        if (stopped.compareAndSet(false, true)) runCatching { recorder?.stop() }
    }
}
