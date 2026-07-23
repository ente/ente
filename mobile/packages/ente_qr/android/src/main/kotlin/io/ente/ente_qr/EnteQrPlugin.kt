package io.ente.ente_qr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import androidx.annotation.NonNull
import de.markusfisch.android.zxingcpp.ZxingCpp
import de.markusfisch.android.zxingcpp.ZxingCpp.Binarizer
import de.markusfisch.android.zxingcpp.ZxingCpp.ReaderOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.Executors

/** EnteQrPlugin */
class EnteQrPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private val executor = Executors.newSingleThreadExecutor()

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ente_qr")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "scanQrFromImage" -> {
        val imagePath = call.argument<String>("imagePath")
        if (imagePath == null) {
          result.success(mapOf(
            "success" to false,
            "error" to "Image path is required"
          ))
          return
        }

        executor.execute {
          val tryOriginalResolution =
            call.argument<Boolean>("tryOriginalResolution") ?: false

          val qrResult = try {
            scanQrCode(imagePath, tryOriginalResolution)
          } catch (e: Exception) {
            mapOf("success" to false, "error" to "Error scanning QR code: ${e.message}")
          }
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.success(qrResult)
          }
        }
      }
      "scanAllQrFromImage" -> {
        val imagePath = call.argument<String>("imagePath")
        if (imagePath == null) {
          result.success(mapOf(
            "success" to false,
            "error" to "Image path is required"
          ))
          return
        }

        executor.execute {
          val qrResult = try {
            scanAllQrCodes(imagePath)
          } catch (e: Exception) {
            mapOf("success" to false, "error" to "Error scanning QR codes: ${e.message}")
          }
          android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.success(qrResult)
          }
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  /**
   * Load a bitmap with efficient downsampling and EXIF orientation correction.
   * Uses two-pass decoding: first get dimensions, then load at target size.
   */
  private fun loadBitmap(imagePath: String, maxDimension: Int? = 1024): Bitmap? {
    // Pass 1: get dimensions without loading pixels
    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(imagePath, opts)
    val rawW = opts.outWidth
    val rawH = opts.outHeight
    if (rawW <= 0 || rawH <= 0) return null

    // Pass 2: load with downsampling
    var sampleSize = 1
    if (maxDimension != null) {
      while (rawW / (sampleSize * 2) >= maxDimension ||
             rawH / (sampleSize * 2) >= maxDimension) {
        sampleSize *= 2
      }
    }
    val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
    val bitmap = try {
      BitmapFactory.decodeFile(imagePath, decodeOpts)
    } catch (_: OutOfMemoryError) {
      null
    } ?: return null

    // Apply EXIF orientation
    return try {
      val exif = ExifInterface(imagePath)
      val orientation = exif.getAttributeInt(
        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
      )
      val matrix = Matrix()
      when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
        ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
        ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
        else -> return bitmap
      }
      val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
      if (rotated !== bitmap) bitmap.recycle()
      rotated
    } catch (_: Exception) {
      bitmap
    }
  }

  private fun readQrContent(bitmap: Bitmap): String? {
    val options = createReaderOptions()
    val results = ZxingCpp.readBitmap(
      bitmap, 0, 0, bitmap.width, bitmap.height, 0, options
    )

    if (results != null && results.isNotEmpty()) {
      val text = results[0].text
      if (text.isNotEmpty()) {
        return text
      }
    }

    // Fallback: try GlobalHistogram binarizer
    options.binarizer = Binarizer.GLOBAL_HISTOGRAM
    val fallbackResults = ZxingCpp.readBitmap(
      bitmap, 0, 0, bitmap.width, bitmap.height, 0, options
    )
    if (fallbackResults != null && fallbackResults.isNotEmpty()) {
      val text = fallbackResults[0].text
      if (text.isNotEmpty()) {
        return text
      }
    }

    return null
  }

  private fun createReaderOptions(): ReaderOptions {
    return ReaderOptions().apply {
      formats = setOf(ZxingCpp.BarcodeFormat.QRCode)
      tryHarder = true
      tryRotate = true
      tryInvert = true
      tryDownscale = true
      binarizer = Binarizer.LOCAL_AVERAGE
    }
  }

  // ── Main scan methods ─────────────────────────────────────────────

  private fun scanQrCode(
    imagePath: String,
    tryOriginalResolution: Boolean = false,
  ): Map<String, Any> {
    val file = File(imagePath)
    if (!file.exists()) {
      return mapOf("success" to false, "error" to "Image file not found: $imagePath")
    }

    if (tryOriginalResolution) {
      val originalBitmap = loadBitmap(imagePath, maxDimension = null)
      if (originalBitmap != null) {
        try {
          val text = readQrContent(originalBitmap)
          if (text != null) {
            return mapOf("success" to true, "content" to text)
          }
        } finally {
          originalBitmap.recycle()
        }
      }
    }

    val bitmap = loadBitmap(imagePath)
      ?: return mapOf("success" to false, "error" to "Unable to decode image file")

    try {
      val text = readQrContent(bitmap)
      if (text != null) {
        return mapOf("success" to true, "content" to text)
      }

      return mapOf("success" to false, "error" to "No QR code found in image")
    } finally {
      bitmap.recycle()
    }
  }

  private fun scanAllQrCodes(imagePath: String): Map<String, Any> {
    val file = File(imagePath)
    if (!file.exists()) {
      return mapOf("success" to false, "error" to "Image file not found: $imagePath")
    }

    val bitmap = loadBitmap(imagePath)
      ?: return mapOf("success" to false, "error" to "Unable to decode image file")

    try {
      val imgWidth = bitmap.width.toDouble()
      val imgHeight = bitmap.height.toDouble()
      val options = createReaderOptions()

      val results = ZxingCpp.readBitmap(
        bitmap, 0, 0, bitmap.width, bitmap.height, 0, options
      )

      if (results != null && results.isNotEmpty()) {
        val detections = buildDetections(results, imgWidth, imgHeight)
        if (detections.isNotEmpty()) {
          return mapOf("success" to true, "detections" to detections)
        }
      }

      // Fallback: try GlobalHistogram binarizer
      options.binarizer = Binarizer.GLOBAL_HISTOGRAM
      val fallbackResults = ZxingCpp.readBitmap(
        bitmap, 0, 0, bitmap.width, bitmap.height, 0, options
      )
      if (fallbackResults != null && fallbackResults.isNotEmpty()) {
        val detections = buildDetections(fallbackResults, imgWidth, imgHeight)
        if (detections.isNotEmpty()) {
          return mapOf("success" to true, "detections" to detections)
        }
      }

      return mapOf("success" to false, "error" to "No QR code found in image")
    } finally {
      bitmap.recycle()
    }
  }

  private fun buildDetections(
    results: List<ZxingCpp.Result>,
    imgWidth: Double,
    imgHeight: Double,
  ): List<Map<String, Any>> {
    val detections = mutableListOf<Map<String, Any>>()

    for (qrResult in results) {
      val text = qrResult.text ?: continue
      if (text.isEmpty()) continue

      val position = qrResult.position ?: continue
      val points = listOf(
        position.topLeft,
        position.topRight,
        position.bottomRight,
        position.bottomLeft,
      )

      var minX = Float.MAX_VALUE
      var minY = Float.MAX_VALUE
      var maxX = -Float.MAX_VALUE
      var maxY = -Float.MAX_VALUE

      for (point in points) {
        val px = point.x.toFloat()
        val py = point.y.toFloat()
        if (px < minX) minX = px
        if (py < minY) minY = py
        if (px > maxX) maxX = px
        if (py > maxY) maxY = py
      }

      // Add padding around finder patterns
      val padX = (maxX - minX) * 0.15f
      val padY = (maxY - minY) * 0.15f
      minX = (minX - padX).coerceAtLeast(0f)
      minY = (minY - padY).coerceAtLeast(0f)
      maxX = (maxX + padX).coerceAtMost(imgWidth.toFloat())
      maxY = (maxY + padY).coerceAtMost(imgHeight.toFloat())

      detections.add(mapOf(
        "content" to text,
        "x" to (minX / imgWidth),
        "y" to (minY / imgHeight),
        "width" to ((maxX - minX) / imgWidth),
        "height" to ((maxY - minY) / imgHeight),
      ))
    }

    return detections
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    executor.shutdown()
  }
}
