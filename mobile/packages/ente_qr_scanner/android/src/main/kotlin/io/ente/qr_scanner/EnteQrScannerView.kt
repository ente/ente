package io.ente.qr_scanner

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Surface
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.TorchState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class EnteQrScannerView(
    private val context: Context,
    messenger: BinaryMessenger,
    platformViewId: Int,
    private val overlay: EnteQrScannerOverlay,
    private val activityProvider: () -> Activity?,
    private val permissionRequester: ((Boolean) -> Unit) -> Unit,
) : PlatformView,
    MethodChannel.MethodCallHandler {
    private val rootView = FrameLayout(context)
    private val previewView = PreviewView(context)
    private val channel = MethodChannel(messenger, "io.ente.qr_scanner/view_$platformViewId")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var targetRotation = Surface.ROTATION_0
    private var isPaused = false
    private var isDisposed = false
    private var lastEmittedText: String? = null
    private var lastEmittedAtMs = 0L

    private val focusRunnable = object : Runnable {
        override fun run() {
            if (!isDisposed && !isPaused) {
                updateTargetRotation()
                focusOnScanWindow()
                mainHandler.postDelayed(this, focusIntervalMs)
            }
        }
    }

    init {
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER
        rootView.addView(
            previewView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        channel.setMethodCallHandler(this)
        requestPermissionAndStart()
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (isDisposed) {
            return
        }
        isDisposed = true
        stopFocusLoop()
        cameraProvider?.unbindAll()
        cameraProvider = null
        camera = null
        preview = null
        imageAnalysis = null
        channel.setMethodCallHandler(null)
        analysisExecutor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pause" -> {
                pause()
                result.success(null)
            }
            "resume" -> {
                resume()
                result.success(null)
            }
            "getTorchStatus" -> result.success(torchStatus())
            "toggleTorch" -> toggleTorch(result)
            "dispose" -> {
                result.success(null)
                dispose()
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermissionAndStart() {
        permissionRequester { granted ->
            mainHandler.post {
                if (isDisposed) {
                    return@post
                }
                if (granted) {
                    startCamera()
                } else {
                    emitError("Camera permission denied")
                }
            }
        }
    }

    private fun startCamera() {
        if (isDisposed || isPaused) {
            return
        }
        val activity = activityProvider()
        val lifecycleOwner = activity as? LifecycleOwner
        if (activity == null || lifecycleOwner == null) {
            emitError("Scanner activity is unavailable")
            return
        }

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener(
            {
                try {
                    val provider = cameraProviderFuture.get()
                    cameraProvider = provider
                    bindCamera(provider, lifecycleOwner)
                } catch (e: Exception) {
                    emitError("Failed to start camera: ${e.message}")
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bindCamera(
        provider: ProcessCameraProvider,
        lifecycleOwner: LifecycleOwner,
    ) {
        if (isDisposed || isPaused) {
            return
        }

        targetRotation = currentTargetRotation()
        val preview = Preview.Builder()
            .setTargetRotation(targetRotation)
            .build()
            .also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
        val imageAnalysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(Size(1280, 720))
            .setTargetRotation(targetRotation)
            .build()
            .also {
                it.setAnalyzer(
                    analysisExecutor,
                    QrFrameAnalyzer(
                        overlay = overlay,
                        previewView = previewView,
                        onQrCode = ::emitCode,
                    ),
                )
            }

        try {
            provider.unbindAll()
            this.preview = preview
            this.imageAnalysis = imageAnalysis
            camera = provider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageAnalysis,
            )
            startFocusLoop()
            emitTorchStatus()
        } catch (e: Exception) {
            emitError("Failed to bind camera: ${e.message}")
        }
    }

    private fun pause() {
        isPaused = true
        stopFocusLoop()
        cameraProvider?.unbindAll()
        camera = null
        preview = null
        imageAnalysis = null
    }

    private fun resume() {
        if (isDisposed || !isPaused) {
            return
        }
        isPaused = false
        startCamera()
    }

    private fun torchStatus(): Boolean? {
        val currentCamera = camera ?: return null
        if (!currentCamera.cameraInfo.hasFlashUnit()) {
            return null
        }
        return currentCamera.cameraInfo.torchState.value == TorchState.ON
    }

    private fun toggleTorch(result: MethodChannel.Result) {
        val currentCamera = camera
        if (currentCamera == null || !currentCamera.cameraInfo.hasFlashUnit()) {
            result.success(null)
            return
        }

        val enableTorch = currentCamera.cameraInfo.torchState.value != TorchState.ON
        val future = currentCamera.cameraControl.enableTorch(enableTorch)
        future.addListener(
            {
                emitTorchStatus()
                result.success(null)
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun emitCode(text: String) {
        val now = System.currentTimeMillis()
        if (lastEmittedText == text && now - lastEmittedAtMs < duplicateCooldownMs) {
            return
        }
        lastEmittedText = text
        lastEmittedAtMs = now
        mainHandler.post {
            if (!isDisposed && !isPaused) {
                channel.invokeMethod("onCode", text)
            }
        }
    }

    private fun emitError(message: String) {
        mainHandler.post {
            if (!isDisposed) {
                channel.invokeMethod("onError", message)
            }
        }
    }

    private fun emitTorchStatus() {
        val status = torchStatus()
        mainHandler.post {
            if (!isDisposed) {
                channel.invokeMethod("onTorchStatusChanged", status)
            }
        }
    }

    private fun startFocusLoop() {
        stopFocusLoop()
        updateTargetRotation()
        focusOnScanWindow()
        mainHandler.postDelayed(focusRunnable, focusIntervalMs)
    }

    private fun stopFocusLoop() {
        mainHandler.removeCallbacks(focusRunnable)
    }

    private fun focusOnScanWindow() {
        val currentCamera = camera ?: return
        val width = previewView.width
        val height = previewView.height
        if (width <= 0 || height <= 0) {
            return
        }

        val point = previewView.meteringPointFactory.createPoint(
            width / 2f,
            height / 2f,
        )
        val action = FocusMeteringAction.Builder(
            point,
            FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE,
        )
            .setAutoCancelDuration(3, TimeUnit.SECONDS)
            .build()
        currentCamera.cameraControl.startFocusAndMetering(action)
    }

    private fun currentTargetRotation(): Int = previewView.display?.rotation ?: Surface.ROTATION_0

    private fun updateTargetRotation() {
        val rotation = currentTargetRotation()
        if (rotation == targetRotation) {
            return
        }
        targetRotation = rotation
        preview?.targetRotation = rotation
        imageAnalysis?.targetRotation = rotation
    }

    companion object {
        private const val duplicateCooldownMs = 1500L
        private const val focusIntervalMs = 1500L
    }
}
