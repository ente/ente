package io.ente.qr_scanner

import android.graphics.Rect
import android.view.View
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import de.markusfisch.android.zxingcpp.ZxingCpp
import de.markusfisch.android.zxingcpp.ZxingCpp.Binarizer
import de.markusfisch.android.zxingcpp.ZxingCpp.ReaderOptions
import kotlin.math.min
import kotlin.math.roundToInt

class QrFrameAnalyzer(
    private val overlay: EnteQrScannerOverlay,
    private val previewView: View,
    private val onQrCode: (String) -> Unit,
) : ImageAnalysis.Analyzer {
    override fun analyze(image: ImageProxy) {
        try {
            val yData = copyYPlane(image)
            val cropRect = scanCropRect(image.width, image.height)
            val rotation = image.imageInfo.rotationDegrees
            val text = decode(yData, image.width, cropRect, rotation)
            if (!text.isNullOrEmpty()) {
                onQrCode(text)
            }
        } finally {
            image.close()
        }
    }

    private fun decode(
        yData: ByteArray,
        width: Int,
        cropRect: Rect,
        rotation: Int,
    ): String? {
        val localAverageOptions = readerOptions(Binarizer.LOCAL_AVERAGE)
        val localAverageResults = ZxingCpp.readByteArray(
            yData,
            width,
            cropRect,
            rotation,
            localAverageOptions,
        )
        val localAverageText = localAverageResults?.firstOrNull()?.text
        if (!localAverageText.isNullOrEmpty()) {
            return localAverageText
        }

        val globalHistogramOptions = readerOptions(Binarizer.GLOBAL_HISTOGRAM)
        val globalHistogramResults = ZxingCpp.readByteArray(
            yData,
            width,
            cropRect,
            rotation,
            globalHistogramOptions,
        )
        return globalHistogramResults?.firstOrNull()?.text
    }

    private fun readerOptions(binarizer: Binarizer): ReaderOptions {
        return ReaderOptions().apply {
            formats = setOf(ZxingCpp.BarcodeFormat.QRCode)
            tryHarder = true
            tryRotate = true
            tryInvert = true
            tryDownscale = true
            maxNumberOfSymbols = 1
            this.binarizer = binarizer
        }
    }

    private fun scanCropRect(width: Int, height: Int): Rect {
        val frameMin = min(width, height).coerceAtLeast(1)
        val viewMin = min(previewView.width, previewView.height)
        val density = previewView.resources.displayMetrics.density
        val scanFraction = if (viewMin > 0) {
            ((overlay.cutOutSize * density) / viewMin).coerceIn(0.2, 1.0)
        } else {
            0.7
        }
        val cropSize = (frameMin * scanFraction).roundToInt().coerceIn(1, frameMin)
        val left = ((width - cropSize) / 2).coerceAtLeast(0)
        val top = ((height - cropSize) / 2).coerceAtLeast(0)
        return Rect(left, top, left + cropSize, top + cropSize)
    }

    private fun copyYPlane(image: ImageProxy): ByteArray {
        val plane = image.planes[0]
        val buffer = plane.buffer.duplicate()
        val width = image.width
        val height = image.height
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val data = ByteArray(width * height)
        var outputIndex = 0

        for (row in 0 until height) {
            val rowOffset = row * rowStride
            for (column in 0 until width) {
                data[outputIndex++] = buffer.get(rowOffset + column * pixelStride)
            }
        }

        return data
    }
}
