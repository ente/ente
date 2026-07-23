import AVFoundation
import Flutter
import UIKit

private final class EnteQrScannerPreviewView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

final class EnteQrScannerView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate {
  private let containerView: EnteQrScannerPreviewView
  private let channel: FlutterMethodChannel
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "io.ente.qr_scanner.session")
  private let metadataQueue = DispatchQueue(label: "io.ente.qr_scanner.metadata")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var metadataOutput: AVCaptureMetadataOutput?
  private var captureDevice: AVCaptureDevice?
  private var isConfigured = false
  private var isPaused = false
  private var isDisposed = false
  private var lastEmittedText: String?
  private var lastEmittedAt = Date.distantPast
  private let supportedMetadataTypes: [AVMetadataObject.ObjectType] = [.qr]

  init(
    frame: CGRect,
    platformViewId: Int64,
    args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    containerView = EnteQrScannerPreviewView(frame: frame)
    channel = FlutterMethodChannel(
      name: "io.ente.qr_scanner/view_\(platformViewId)",
      binaryMessenger: messenger
    )
    super.init()
    containerView.backgroundColor = .black
    containerView.onLayout = { [weak self] in
      self?.updatePreviewLayout()
    }
    channel.setMethodCallHandler(handle)
    let tapRecognizer = UITapGestureRecognizer(
      target: self,
      action: #selector(handleTapToFocus(_:))
    )
    containerView.addGestureRecognizer(tapRecognizer)
    requestPermissionAndStart()
  }

  func view() -> UIView {
    containerView
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pause":
      pause()
      result(nil)
    case "resume":
      resume()
      result(nil)
    case "getTorchStatus":
      result(torchStatus())
    case "toggleTorch":
      toggleTorch(result: result)
    case "dispose":
      result(nil)
      dispose()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermissionAndStart() {
    #if targetEnvironment(simulator)
      return
    #else
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        configureAndStart()
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
          if granted {
            self?.configureAndStart()
          } else {
            self?.emitError("Camera permission denied")
          }
        }
      default:
        emitError("Camera permission denied")
      }
    #endif
  }

  private func configureAndStart() {
    sessionQueue.async { [weak self] in
      guard let self = self, !self.isDisposed else {
        return
      }
      if !self.isConfigured {
        self.configureSession()
      }
      if !self.isPaused && !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  private func configureSession() {
    session.beginConfiguration()
    if session.canSetSessionPreset(.hd1920x1080) {
      session.sessionPreset = .hd1920x1080
    } else if session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }

    guard
      let device = makeCaptureDevice(),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      emitError("Back camera is unavailable")
      return
    }
    session.addInput(input)
    captureDevice = device

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      emitError("QR metadata output is unavailable")
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: metadataQueue)
    let enabledMetadataTypes = supportedMetadataTypes.filter {
      output.availableMetadataObjectTypes.contains($0)
    }
    guard !enabledMetadataTypes.isEmpty else {
      session.commitConfiguration()
      emitError("QR metadata output is unavailable")
      return
    }
    output.metadataObjectTypes = enabledMetadataTypes
    metadataOutput = output

    session.commitConfiguration()
    isConfigured = true
    configureFocusAndExposure(device)
    emitTorchStatus()

    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.previewLayer == nil else {
        return
      }
      let layer = AVCaptureVideoPreviewLayer(session: self.session)
      layer.videoGravity = .resizeAspectFill
      self.previewLayer = layer
      self.containerView.layer.insertSublayer(layer, at: 0)
      self.updatePreviewLayout()
    }
  }

  private func makeCaptureDevice() -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera],
      mediaType: .video,
      position: .back
    ).devices.first ?? AVCaptureDevice.default(for: .video)
  }

  @objc private func handleTapToFocus(_ recognizer: UITapGestureRecognizer) {
    guard
      recognizer.state == .ended,
      let device = captureDevice,
      let previewLayer = previewLayer
    else {
      return
    }
    let layerPoint = recognizer.location(in: containerView)
    let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
    configureFocusAndExposure(device, at: devicePoint)
  }

  private func configureFocusAndExposure(
    _ device: AVCaptureDevice,
    at point: CGPoint = CGPoint(x: 0.5, y: 0.5)
  ) {
    do {
      try device.lockForConfiguration()
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = point
      }
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = point
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
    } catch {
      emitError("Failed to configure camera focus")
    }
  }

  private func updatePreviewLayout() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.updatePreviewLayout()
      }
      return
    }

    previewLayer?.frame = containerView.bounds
    metadataOutput?.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
  }

  private func pause() {
    isPaused = true
    sessionQueue.async { [weak self] in
      guard let self = self, self.session.isRunning else {
        return
      }
      self.session.stopRunning()
    }
  }

  private func resume() {
    guard !isDisposed else {
      return
    }
    isPaused = false
    configureAndStart()
  }

  private func torchStatus() -> Bool? {
    guard let device = captureDevice, device.hasTorch else {
      return nil
    }
    return device.torchMode == .on
  }

  private func toggleTorch(result: @escaping FlutterResult) {
    guard let device = captureDevice, device.hasTorch else {
      result(nil)
      return
    }
    do {
      try device.lockForConfiguration()
      device.torchMode = device.torchMode == .on ? .off : .on
      device.unlockForConfiguration()
      emitTorchStatus()
      result(nil)
    } catch {
      result(FlutterError(
        code: "torch_error",
        message: "Failed to toggle torch",
        details: nil
      ))
    }
  }

  private func dispose() {
    guard !isDisposed else {
      return
    }
    isDisposed = true
    channel.setMethodCallHandler(nil)
    sessionQueue.async { [weak self] in
      guard let self = self else {
        return
      }
      if self.session.isRunning {
        self.session.stopRunning()
      }
      self.session.inputs.forEach { self.session.removeInput($0) }
      self.session.outputs.forEach { self.session.removeOutput($0) }
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard
      !isDisposed,
      !isPaused,
      let readableObject = metadataObjects
        .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
        .first,
      supportedMetadataTypes.contains(readableObject.type),
      let payload = readableObject.stringValue,
      !payload.isEmpty
    else {
      return
    }
    emitCode(payload)
  }

  private func emitCode(_ text: String) {
    let now = Date()
    if lastEmittedText == text && now.timeIntervalSince(lastEmittedAt) < 1.5 {
      return
    }
    lastEmittedText = text
    lastEmittedAt = now
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.isDisposed, !self.isPaused else {
        return
      }
      self.channel.invokeMethod("onCode", arguments: text)
    }
  }

  private func emitError(_ message: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.isDisposed else {
        return
      }
      self.channel.invokeMethod("onError", arguments: message)
    }
  }

  private func emitTorchStatus() {
    let status = torchStatus()
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.isDisposed else {
        return
      }
      self.channel.invokeMethod("onTorchStatusChanged", arguments: status)
    }
  }
}
