import AVFoundation
import AVKit
import Flutter
import UIKit

// Plays a local video file or an HLS stream in a Picture-in-Picture window.
//
// The player lives outside the Flutter widget tree, so PiP keeps playing
// after the viewer closes. The plugin never deletes files; it reports the
// paths it holds so Dart can delay deleting them.
public final class EntePipPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.ente.photos/pip",
            binaryMessenger: registrar.messenger()
        )
        let instance = EntePipPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private struct Playback {
        let item: AVPlayerItem
        let path: String
        let speed: Float
        let loop: Bool
        // AVURLAsset holds its resource loader delegate weakly.
        let streamLoader: HLSStreamLoader?
    }

    private struct PendingStart {
        let id: Int
        let playback: Playback
        let result: FlutterResult
    }

    private static let startTimeout: TimeInterval = 10
    private static let restoreAnswerTimeout: TimeInterval = 2
    private static let handBackTimeout: TimeInterval = 4

    private let channel: FlutterMethodChannel
    private let player: AVPlayer = {
        let player = AVPlayer()
        // A locked phone hides the PiP window; keep playing anyway.
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        return player
    }()
    private var playerView: PlayerView?
    private var pipController: AVPictureInPictureController?

    private var current: Playback?
    private var pendingStart: PendingStart?
    private var nextStartID = 0
    private var statusObservation: NSKeyValueObservation?
    private var possibleObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    private var isHandingBack = false
    private var handBackID = 0

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(AVPictureInPictureController.isPictureInPictureSupported())
        case "start":
            start(arguments: call.arguments, result: result)
        case "finishRestore":
            endHandBack()
            result(nil)
        case "stop":
            cancelPendingStart()
            cancelHandBack()
            tearDown()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Starting

    private func start(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let path = args["path"] as? String,
              let positionMs = args["positionMs"] as? Int,
              let muted = args["muted"] as? Bool,
              let speed = args["speed"] as? Double,
              let loop = args["loop"] as? Bool
        else {
            result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            return
        }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            result(FlutterError(code: "UNSUPPORTED", message: nil, details: nil))
            return
        }

        var streamLoader: HLSStreamLoader?
        if let playlist = args["hlsPlaylist"] as? String {
            guard let loader = HLSStreamLoader(playlist: playlist) else {
                result(FlutterError(code: "INVALID_STREAM", message: nil, details: nil))
                return
            }
            streamLoader = loader
        } else if !FileManager.default.fileExists(atPath: path) {
            result(FlutterError(code: "FILE_MISSING", message: nil, details: nil))
            return
        }

        cancelPendingStart()
        cancelHandBack()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            result(FlutterError(code: "AUDIO_SESSION", message: error.localizedDescription, details: nil))
            return
        }

        guard preparePipController() != nil else {
            result(FlutterError(code: "NO_WINDOW", message: nil, details: nil))
            return
        }

        let asset = streamLoader?.asset ?? AVURLAsset(url: URL(fileURLWithPath: path))
        let item = AVPlayerItem(asset: asset)
        nextStartID += 1
        let id = nextStartID
        let playback = Playback(
            item: item, path: path, speed: Float(speed), loop: loop, streamLoader: streamLoader
        )
        pendingStart = PendingStart(id: id, playback: playback, result: result)
        reportHeldPaths()

        player.replaceCurrentItem(with: item)
        player.isMuted = muted
        // Pausing at the end would stop a loop on a locked phone, where a
        // background app can't start playback again.
        player.actionAtItemEnd = loop ? .none : .pause

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.itemStatusChanged(item, positionMs: positionMs)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startTimeout) { [weak self] in
            guard let self, self.pendingStart?.id == id else { return }
            self.failPendingStart(code: "TIMEOUT", message: nil)
        }
    }

    private func itemStatusChanged(_ item: AVPlayerItem, positionMs: Int) {
        guard pendingStart?.playback.item === item else { return }
        switch item.status {
        case .failed:
            failPendingStart(code: "LOAD_FAILED", message: item.error?.localizedDescription)
        case .readyToPlay:
            statusObservation = nil
            let position = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
            player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.beginPlayback(of: item)
                }
            }
        default:
            break
        }
    }

    private func beginPlayback(of item: AVPlayerItem) {
        guard let pending = pendingStart, pending.playback.item === item,
              let controller = pipController
        else { return }

        let speed = pending.playback.speed
        if #available(iOS 16.0, *) {
            // Used by the PiP window's play button.
            player.defaultRate = speed
        }
        player.rate = speed

        if controller.isPictureInPictureActive {
            completePendingStart()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            possibleObservation = controller.observe(
                \.isPictureInPicturePossible, options: [.new]
            ) { [weak self] controller, _ in
                DispatchQueue.main.async {
                    guard let self, controller.isPictureInPicturePossible,
                          self.pendingStart?.playback.item === item
                    else { return }
                    self.possibleObservation = nil
                    controller.startPictureInPicture()
                }
            }
        }
    }

    private func completePendingStart() {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        possibleObservation = nil
        setCurrent(pending.playback)
        pending.result(nil)
    }

    private func failPendingStart(code: String, message: String?) {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        tearDown()
        pending.result(FlutterError(code: code, message: message, details: nil))
    }

    // Fails a start that is still loading without closing an open PiP window.
    private func cancelPendingStart() {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        statusObservation = nil
        possibleObservation = nil
        if let current {
            player.replaceCurrentItem(with: current.item)
        }
        reportHeldPaths()
        pending.result(FlutterError(code: "CANCELLED", message: nil, details: nil))
    }

    // MARK: - Current video

    private func setCurrent(_ playback: Playback?) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        current = playback
        if let playback {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playback.item,
                queue: .main
            ) { [weak self] _ in
                self?.playbackEnded()
            }
        }
        reportHeldPaths()
    }

    private func playbackEnded() {
        guard let current, current.loop else { return }
        player.seek(to: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.current?.item === current.item, self.player.rate == 0
                else { return }
                self.player.rate = current.speed
            }
        }
    }

    private func reportHeldPaths() {
        let paths = Set([current?.path, pendingStart?.playback.path].compactMap { $0 })
        channel.invokeMethod("held", arguments: ["paths": Array(paths)])
    }

    // MARK: - Player view

    // PiP needs an AVPlayerLayer in a window. It sits behind the Flutter
    // view, so it is never visible except during a hand-back.
    private func preparePipController() -> AVPictureInPictureController? {
        if let pipController, playerView?.window != nil {
            return pipController
        }
        guard let window = Self.keyWindow() else { return nil }

        let view = PlayerView(frame: window.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        window.insertSubview(view, at: 0)

        guard let controller = AVPictureInPictureController(playerLayer: view.playerLayer) else {
            view.removeFromSuperview()
            return nil
        }
        controller.delegate = self
        playerView?.removeFromSuperview()
        playerView = view
        pipController = controller
        return controller
    }

    private static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    // MARK: - Hand-back

    // Shows the PiP video above the app where the viewer draws its video, so
    // iOS animates the window into it while the viewer catches up underneath.
    private func beginHandBack() {
        guard let playerView, let superview = playerView.superview else { return }
        isHandingBack = true
        handBackID += 1
        let id = handBackID
        player.isMuted = true
        superview.bringSubviewToFront(playerView)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handBackTimeout) { [weak self] in
            guard let self, self.handBackID == id else { return }
            self.endHandBack()
        }
    }

    private func cancelHandBack() {
        guard isHandingBack, let playerView else { return }
        isHandingBack = false
        handBackID += 1
        playerView.superview?.sendSubviewToBack(playerView)
    }

    private func endHandBack() {
        guard isHandingBack, let playerView else { return }
        isHandingBack = false
        handBackID += 1
        UIView.animate(withDuration: 0.25, animations: {
            playerView.alpha = 0
        }, completion: { [weak self] _ in
            guard let self else { return }
            playerView.superview?.sendSubviewToBack(playerView)
            playerView.alpha = 1
            let isPipActive = self.pipController?.isPictureInPictureActive ?? false
            if self.pendingStart == nil && !isPipActive {
                self.tearDown()
            }
        })
    }

    private func tearDown() {
        statusObservation = nil
        possibleObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let pipController, pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        }
        setCurrent(nil)
    }
}

extension EntePipPlugin: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        completePendingStart()
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        failPendingStart(code: "START_FAILED", message: error.localizedDescription)
    }

    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        // A pending start reopens PiP, and a hand-back tears down when it ends.
        if pendingStart == nil && !isHandingBack {
            tearDown()
        }
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let current else {
            completionHandler(false)
            return
        }
        let seconds = player.currentTime().seconds
        let positionMs = seconds.isFinite ? max(Int(seconds * 1000), 0) : 0

        // Answering false makes iOS close the window instead of animating it
        // into the app, which is right when no viewer takes over.
        var answered = false
        let answer: (Bool) -> Void = { [weak self] handled in
            guard !answered else { return }
            answered = true
            if handled {
                self?.beginHandBack()
            }
            completionHandler(handled)
        }
        channel.invokeMethod(
            "restore",
            arguments: ["path": current.path, "positionMs": positionMs]
        ) { result in
            DispatchQueue.main.async { answer((result as? Bool) ?? false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreAnswerTimeout) {
            answer(false)
        }
    }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

// Serves an HLS playlist and its keys from memory.
//
// AVPlayer can't open a playlist from a file, and doesn't accept `data:` key
// URIs, so both are served under custom schemes. Segments still load over
// HTTPS from their URLs in the playlist.
private final class HLSStreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    private static let playlistScheme = "ente-pip-playlist"
    private static let keyScheme = "ente-pip-key"
    private static let dataKeyURI = try! NSRegularExpression(
        pattern: #"URI="data:text/plain;base64,([A-Za-z0-9+/]+={0,2})""#
    )

    let asset: AVURLAsset
    private let playlist: Data
    private let keys: [String: Data]
    private let queue = DispatchQueue(label: "io.ente.photos.pip.hls")

    init?(playlist text: String) {
        var rewritten = text
        var keys: [String: Data] = [:]
        let matches = Self.dataKeyURI.matches(in: text, range: NSRange(text.startIndex..., in: text))
        // In reverse, so replacing a match keeps the earlier ranges valid.
        for (index, match) in matches.enumerated().reversed() {
            guard let whole = Range(match.range, in: text),
                  let base64 = Range(match.range(at: 1), in: text),
                  let key = Data(base64Encoded: String(text[base64]))
            else { return nil }
            keys["\(index)"] = key
            rewritten.replaceSubrange(whole, with: "URI=\"\(Self.keyScheme)://\(index)\"")
        }
        guard !keys.isEmpty,
              let url = URL(string: "\(Self.playlistScheme)://preview.m3u8")
        else { return nil }
        self.playlist = Data(rewritten.utf8)
        self.keys = keys
        self.asset = AVURLAsset(url: url)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        let data: Data
        let contentType: String
        switch url.scheme {
        case Self.playlistScheme:
            data = playlist
            contentType = "public.m3u-playlist"
        case Self.keyScheme:
            guard let key = url.host.flatMap({ keys[$0] }) else { return false }
            data = key
            contentType = "public.data"
        default:
            return false
        }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
        return true
    }
}
