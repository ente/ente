import Foundation
import AVFoundation
import Combine

enum VoiceInputFailure: Equatable {
    case permission, microphone, noSpeech, interrupted, captureInterrupted
    case modelUnavailable, memoryUnavailable, storageFull, download, fileAccess, transcription
    case insertion, incomplete

    var message: String {
        switch self {
        case .permission:
            return "Microphone permission is required. Enable it in Settings."
        case .microphone:
            return "Could not start the microphone. Tap the microphone to try again."
        case .noSpeech:
            return "No speech detected. Tap the microphone to try again."
        case .interrupted:
            return "Voice input stopped. Review the available text or try again."
        case .captureInterrupted:
            return "Audio capture interrupted. Some words may be missing; review the text."
        case .modelUnavailable:
            return "The voice model is unavailable. Tap the microphone to download it again."
        case .memoryUnavailable:
            return "Not enough free memory for voice input. Close other apps and try again."
        case .storageFull:
            return "Not enough storage for voice input. Free up space and try again."
        case .download:
            return "Could not download the voice model. Check your connection and try again."
        case .fileAccess:
            return "Could not access voice model files. Try again."
        case .transcription:
            return "Could not transcribe voice input. Review the available text or try again."
        case .incomplete:
            return "Some words may be missing. Review the text."
        case .insertion:
            return "The draft changed before voice input finished. Tap the microphone to try again."
        }
    }

    static func classify(_ error: Error) -> Self? {
        switch error {
        case is CancellationError, AssetDownloadError.Cancelled, DictationError.Cancelled:
            return nil
        case is ModelMemoryUnavailable:
            return .memoryUnavailable
        case DictationError.NotDownloaded, DictationError.VadNotDownloaded:
            return .modelUnavailable
        case AssetDownloadError.StorageFull, DictationError.StorageFull:
            return .storageFull
        case AssetDownloadError.Io, DictationError.Io:
            return .fileAccess
        case is AssetDownloadError:
            return .download
        case DictationError.InvalidAudio:
            return .captureInterrupted
        default:
            return .transcription
        }
    }
}

enum VoiceInputState: Equatable {
    case idle
    case preparing
    case recording
    case downloading(percent: Int?, queued: Bool)
    case transcribing
    case error(VoiceInputFailure)

    var isRecording: Bool {
        self == .recording
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

}

@MainActor
final class VoiceTranscriptionService: ObservableObject {
    @Published private(set) var active = false {
        didSet { onActivityChanged?() }
    }
    @Published private(set) var snapshot: DictationSnapshot?
    @Published private(set) var audioLevels = Array(repeating: Float.zero, count: 24)
    @Published private(set) var notice: VoiceInputFailure?
    @Published private(set) var state: VoiceInputState = .idle {
        didSet {
            transientErrorTask?.cancel()
            transientErrorTask = nil
            if state == .error(.noSpeech) {
                transientErrorTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self, self.state == .error(.noSpeech) else { return }
                    self.state = .idle
                }
            }
        }
    }
    @Published private(set) var isFinishingSlow = false
    var onActivityChanged: (@MainActor () -> Void)?
    var onInsert: (@MainActor (DictationInsertion, String) -> Bool)?
    private let provider: LlmProvider
    private let assetStore: AssetStore
    private let modelAssets: [Asset]
    private let usesLiveDictation: Bool
    private let logger = EnsuLogging.shared.logger("EnsuVoice")
    private var session: DictationSession?
    private var stream: DictationStream?
    private var recorder: LivePcmRecorder?
    private var task: Task<Void, Never>?
    private var finishingNoticeTask: Task<Void, Never>?
    private var transientErrorTask: Task<Void, Never>?
    private var attemptFinished = false
    private var insertion: DictationInsertion?
    private var makeInsertion: (@MainActor () -> DictationInsertion?)?
    private var generation = UUID()
    private var foreground = true
    private var awaitingPermission = false
    private var startOnForeground = false
    private let notifications = VoiceNotificationTokens()
    @Published private(set) var hasActiveTasks = false {
        didSet { onActivityChanged?() }
    }
    private func diagnostic(_ event: String) {
        #if DEBUG
            logger.info(event)
        #endif
    }

    init(provider: LlmProvider, assetStore: AssetStore) {
        self.provider = provider
        self.assetStore = assetStore
        usesLiveDictation = supportsLiveVoice(
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
        modelAssets = [
            transcriptionModelAsset(),
            voiceActivityModelAsset(),
        ]
        for name in [
            AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification,
        ] {
            notifications.values.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] notification in
                    let route = notification.name == AVAudioSession.routeChangeNotification
                    let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    Task { @MainActor [weak self] in
                        guard let self,
                            self.active,
                            !route || self.recorder?.isRecording == true || self.state.isRecording
                        else { return }
                        let audio = AVAudioSession.sharedInstance()
                        if route,
                            reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue,
                            audio.category == .playAndRecord, audio.mode == .measurement
                        {
                            return
                        }
                        self.diagnostic(
                            "audio_interruption route=\(route) reason=\(reason ?? 0)")
                        self.interrupt()
                    }
                })
        }
    }

    var blocksComposer: Bool {
        guard active else { return false }
        switch state {
        case .idle, .downloading: return false
        default: return true
        }
    }

    func open(makeInsertion: @escaping @MainActor () -> DictationInsertion?) {
        guard !active, !hasActiveTasks else { return }
        generation = UUID()
        self.makeInsertion = makeInsertion
        attemptFinished = false
        isFinishingSlow = false
        session = DictationSession(live: usesLiveDictation)
        snapshot = session?.snapshot()
        active = true
        state = .idle
        notice = nil
        record()
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if active {
            if startOnForeground {
                startOnForeground = false
                record()
            } else if let owner = session {
                refresh(owner, token: generation)
            }
        } else if !awaitingPermission, !startOnForeground {
            if case .downloading = state { return }
            interrupt()
        }
    }

    func composerPreview(original: String) -> DictationInsertionResult? {
        guard active, let insertion, let snapshot else { return nil }
        return try? insertion.preview(
            text: original, voiceText: snapshot.text + snapshot.hypothesis)
    }

    func record() {
        guard active, foreground, !hasActiveTasks, !attemptFinished, let owner = session
        else { return }
        let token = generation
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            guard !awaitingPermission else { return }
            awaitingPermission = true
            AVAudioSession.sharedInstance().requestRecordPermission {
                @Sendable [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    guard self.active else { return }
                    self.awaitingPermission = false
                    if granted {
                        if self.foreground { self.record() } else { self.startOnForeground = true }
                    } else {
                        self.cancel()
                        self.state = .error(.permission)
                    }
                }
            }
            return
        case .denied:
            cancel()
            state = .error(.permission)
            return
        case .granted: break
        @unknown default: return
        }
        hasActiveTasks = true
        notice = nil
        state = .downloading(percent: nil, queued: true)
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.hasActiveTasks = false
                if self.generation == token {
                    self.finishingNoticeTask?.cancel()
                    self.finishingNoticeTask = nil
                    self.recorder?.stop()
                    self.recorder = nil
                    self.stream = nil
                    self.attemptFinished = true
                    self.refresh(owner, token: token)
                }
            }
            do {
                if !self.modelAssets.allSatisfy({ self.assetStore.isDownloaded($0) }) {
                    try await self.assetStore.download(assets: self.modelAssets) {
                        [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token,
                                case .downloading = self.state
                            else { return }
                            self.state = .downloading(
                                percent: progress.totalBytes.map { _ in Int(progress.percentage) },
                                queued: progress.queued)
                        }
                    }
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                guard self.foreground else {
                    self.cancel()
                    return
                }
                guard let insertion = self.makeInsertion?() else {
                    self.cancel()
                    return
                }
                self.insertion = insertion
                self.makeInsertion = nil
                self.state = .preparing
                let recorder: LivePcmRecorder
                do {
                    recorder = try LivePcmRecorder()
                } catch {
                    self.logger.error("Could not prepare the microphone", error)
                    self.notice = .microphone
                    return
                }
                self.recorder = recorder
                let sampleRate = recorder.sampleRate
                let stream = try DictationStream(
                    session: owner, sampleRate: sampleRate, channels: 1)
                self.stream = stream
                let delivery = LiveCaptureDelivery(
                    stream: stream, sampleRate: sampleRate,
                    level: { [weak self] level in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token, self.state.isRecording else {
                                return
                            }
                            self.audioLevels = Array(self.audioLevels.dropFirst()) + [level]
                        }
                    }
                ) {
                    [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        if let error {
                            self.logger.error("Audio capture failed", error)
                        } else {
                            self.logger.warning("Audio capture exceeded its buffer limit")
                        }
                        self.interrupt(reason: .captureInterrupted)
                    }
                }
                let callback = LiveVoiceCallback(
                    ready: { [weak self] in
                        Task { @MainActor [weak self] in
                            let value = owner.snapshot()
                            guard let self, self.generation == token, self.foreground,
                                self.active, self.stream === stream, value.workerActive,
                                value.phase == .listening
                            else { return }
                            do {
                                try recorder.start(delivery: delivery)
                                self.state = .recording
                                self.audioLevels = Array(repeating: 0, count: 24)
                                self.notice = nil
                                self.refresh(owner, token: token)
                            } catch {
                                self.logger.error("Could not start the microphone", error)
                                self.interrupt(reason: .microphone)
                            }
                        }
                    },
                    change: { [weak self] in
                        Task { @MainActor [weak self] in self?.refresh(owner, token: token) }
                    },
                    closed: { [weak self] in
                        delivery.close()
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == token, self.stream === stream
                            else { return }
                            recorder.stop()
                            self.watchFinalization(owner, stream: stream, token: token)
                        }
                    }
                )
                try await self.provider.runLiveVoice(stream: stream, callback: callback)
            } catch {
                let failure = VoiceInputFailure.classify(error)
                if failure != nil { self.logger.error("Voice input failed", error) }
                if self.generation == token, self.notice == nil {
                    self.notice = failure ?? .interrupted
                }
            }
        }
    }

    private func refresh(_ owner: DictationSession, token: UUID) {
        guard generation == token, active else { return }
        let value = owner.snapshot()
        snapshot = value
        guard attemptFinished else {
            if value.phase == .finishing { state = .transcribing }
            return
        }
        guard foreground else { return }
        let text = value.text + value.hypothesis
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let added = hasText && insertion.map { onInsert?($0, text) == true } == true
        let completedState: VoiceInputState
        if added {
            let failure: VoiceInputFailure =
                notice == .transcription ? .incomplete : notice ?? .interrupted
            completedState = value.incomplete ? .error(failure) : .idle
        } else {
            completedState = .error(hasText ? .insertion : notice ?? .noSpeech)
        }
        active = false
        isFinishingSlow = false
        session = nil
        snapshot = nil
        insertion = nil
        makeInsertion = nil
        onInsert = nil
        audioLevels = Array(repeating: 0, count: 24)
        state = completedState
    }

    private func watchFinalization(_ owner: DictationSession, stream: DictationStream, token: UUID)
    {
        guard token == generation, active, self.stream === stream, owner.snapshot().workerActive,
            finishingNoticeTask == nil
        else { return }
        finishingNoticeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.generation == token, self.active, self.stream === stream,
                owner.snapshot().workerActive
            else { return }
            self.isFinishingSlow = true
        }
    }

    func stop() {
        guard let owner = session else { return }
        let reason: DictationStopReason = .done
        _ = try? owner.stop(reason: reason)
        snapshot = owner.snapshot()
        state = .transcribing
        let stream = stream
        if let stream { watchFinalization(owner, stream: stream, token: generation) }
        recorder?.stop(afterDelivery: { try? stream?.stop(reason: reason) })
        if recorder == nil { try? stream?.stop(reason: reason) }
    }

    func interrupt(reason: VoiceInputFailure = .interrupted) {
        guard active, !attemptFinished else { return }
        if case .downloading = state {
            releaseComposer()
            return
        }
        if !hasActiveTasks, stream == nil {
            cancel()
            return
        }
        recorder?.stop()
        try? stream?.abandon(reason: .interruption)
        task?.cancel()
        finishingNoticeTask?.cancel()
        isFinishingSlow = false
        notice = reason
        state = .transcribing
    }

    func releaseComposer() {
        if case .downloading = state {
            makeInsertion = nil
            onInsert = nil
        } else {
            cancel()
        }
    }

    func cancel() {
        awaitingPermission = false
        startOnForeground = false
        generation = UUID()
        finishingNoticeTask?.cancel()
        finishingNoticeTask = nil
        recorder?.stop()
        try? stream?.abandon(reason: .discard)
        task?.cancel()
        active = false
        isFinishingSlow = false
        state = .idle
        snapshot = nil
        session = nil
        insertion = nil
        makeInsertion = nil
        stream = nil
        recorder = nil
        onInsert = nil
    }
}

private final class LiveVoiceCallback: DictationStreamCallback, Sendable {
    let ready: @Sendable () -> Void
    let change: @Sendable () -> Void
    let closed: @Sendable () -> Void
    init(
        ready: @escaping @Sendable () -> Void,
        change: @escaping @Sendable () -> Void,
        closed: @escaping @Sendable () -> Void
    ) {
        self.ready = ready
        self.change = change
        self.closed = closed
    }
    func onReady() { ready() }
    func onChange() { change() }
    func onCaptureClosed() { closed() }
}

@MainActor
private final class LivePcmRecorder {
    private let engine = AVAudioEngine()
    private var delivery: LiveCaptureDelivery?
    private var installed = false
    let sampleRate: UInt32
    var isRecording: Bool { engine.isRunning }

    init() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(
            .playAndRecord, mode: .measurement, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try audio.setActive(true)
        sampleRate = UInt32(engine.inputNode.outputFormat(forBus: 0).sampleRate.rounded())
        guard (8000...48000).contains(sampleRate) else {
            try? audio.setActive(false, options: .notifyOthersOnDeactivation)
            throw CocoaError(.featureUnsupported)
        }
    }

    func start(delivery: LiveCaptureDelivery) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard UInt32(format.sampleRate.rounded()) == sampleRate else {
            throw CocoaError(.featureUnsupported)
        }
        self.delivery = delivery
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(sampleRate / 10), format: format) {
            @Sendable buffer, _ in
            delivery.accept(buffer)
        }
        installed = true
        engine.prepare()
        try engine.start()
    }

    func stop(afterDelivery: (@Sendable () -> Void)? = nil) {
        if installed {
            engine.inputNode.removeTap(onBus: 0)
            installed = false
        }
        delivery?.close()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let afterDelivery {
            if let delivery { delivery.drain(afterDelivery) } else { afterDelivery() }
        }
    }
}

private final class VoiceNotificationTokens: @unchecked Sendable {
    var values: [NSObjectProtocol] = []
    deinit { for value in values { NotificationCenter.default.removeObserver(value) } }
}

final class LiveCaptureDelivery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.ente.ensu.voice.capture", qos: .userInitiated)
    private let lock = NSLock()
    private var accepting = true
    private var framesPending = 0
    private var chunksPending = 0
    private let stream: DictationStream
    private let rate: Int
    private let interrupted: @Sendable (Error?) -> Void
    private let level: @Sendable (Float) -> Void
    private var meterFrames = 0
    private var meterEnergy = 0.0

    init(
        stream: DictationStream, sampleRate: UInt32,
        level: @escaping @Sendable (Float) -> Void,
        interrupted: @escaping @Sendable (Error?) -> Void
    ) {
        self.stream = stream
        rate = Int(sampleRate)
        self.interrupted = interrupted
        self.level = level
    }

    func close() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    func drain(_ completion: @escaping @Sendable () -> Void) { queue.async(execute: completion) }

    func accept(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        accept(frames: frames) {
            guard let channels = buffer.floatChannelData, buffer.format.channelCount > 0 else {
                return nil
            }
            let channelCount = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                for channel in 0..<channelCount { mono[frame] += channels[channel][frame] }
                mono[frame] /= Float(channelCount)
            }
            return mono
        }
    }

    func accept(frames: Int, copySamples: () -> [Float]?) {
        guard frames > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard accepting else { return }
        guard frames <= rate, framesPending + frames <= rate * 2, chunksPending < 128,
            let samples = copySamples()
        else {
            accepting = false
            queue.async { [self] in
                try? stream.abandon(reason: .failure)
                interrupted(nil)
            }
            return
        }
        framesPending += frames
        chunksPending += 1
        queue.async { [self] in
            defer {
                lock.lock()
                framesPending -= frames
                chunksPending -= 1
                lock.unlock()
            }
            do {
                meterFrames += frames
                meterEnergy += samples.reduce(0.0) { $0 + Double($1 * $1) }
                if meterFrames >= rate / 10 {
                    let rms = sqrt(meterEnergy / Double(meterFrames))
                    level(Float(min(1, max(0, (20 * log10(max(rms, 0.00001)) + 55) / 45))))
                    meterFrames = 0
                    meterEnergy = 0
                }
                for start in stride(from: 0, to: frames, by: rate / 10) {
                    let end = min(frames, start + rate / 10)
                    var pcm = Data(count: (end - start) * 2)
                    pcm.withUnsafeMutableBytes { raw in
                        let values = raw.bindMemory(to: Int16.self)
                        for index in start..<end {
                            let value = samples[index]
                            values[index - start] =
                                Int16(min(max(value.isFinite ? value : 0, -1), 1) * 32767)
                                .littleEndian
                        }
                    }
                    if try stream.feed(pcmLe: pcm) == .closed {
                        close()
                        return
                    }
                }
            } catch {
                lock.lock()
                let wasAccepting = accepting
                accepting = false
                lock.unlock()
                if wasAccepting {
                    try? stream.abandon(reason: .failure)
                    interrupted(error)
                }
            }
        }
    }
}
