package io.ente.pdf_renderer

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.LoadParams
import android.graphics.pdf.PdfRenderer
import android.graphics.pdf.RenderParams
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class EntePdfRendererPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private class PdfError(val code: String, message: String) : Exception(message)

  private lateinit var channel: MethodChannel
  private val documents = HashMap<Int, PdfRenderer>()
  private var nextId = 1
  private val executor = Executors.newSingleThreadExecutor()
  private val mainThread = Handler(Looper.getMainLooper())
  private val supportsPasswords = Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "io.ente/pdf_renderer")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    executor.execute {
      documents.values.forEach { it.close() }
      documents.clear()
    }
    executor.shutdown()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    executor.execute {
      try {
        val reply: Any? = when (call.method) {
          "open" -> open(call.argument<String>("path")!!, call.argument<String>("password"))
          "render" -> render(
            call.argument<Int>("id")!!,
            call.argument<Int>("page")!!,
            call.argument<Int>("width")!!,
            call.argument<Int>("height")!!,
          )
          "close" -> {
            documents.remove(call.argument<Int>("id")!!)?.close()
            null
          }
          else -> {
            mainThread.post { result.notImplemented() }
            return@execute
          }
        }
        mainThread.post { result.success(reply) }
      } catch (e: PdfError) {
        mainThread.post { result.error(e.code, e.message, null) }
      } catch (e: Exception) {
        mainThread.post { result.error("invalid", e.toString(), null) }
      }
    }
  }

  private fun open(path: String, password: String?): Map<String, Any> {
    val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
    val renderer = try {
      if (supportsPasswords && password != null) {
        PdfRenderer(descriptor, LoadParams.Builder().setPassword(password).build())
      } else {
        PdfRenderer(descriptor)
      }
    } catch (e: Exception) {
      descriptor.close()
      when {
        e !is SecurityException -> throw e
        !supportsPasswords -> throw PdfError("password_unsupported", "This device cannot unlock PDFs")
        password == null -> throw PdfError("password_required", "PDF needs a password")
        else -> throw PdfError("password_incorrect", "Wrong password")
      }
    }
    val widths = ArrayList<Double>(renderer.pageCount)
    val heights = ArrayList<Double>(renderer.pageCount)
    try {
      for (index in 0 until renderer.pageCount) {
        renderer.openPage(index).use {
          widths.add(it.width.toDouble())
          heights.add(it.height.toDouble())
        }
      }
    } catch (e: Exception) {
      renderer.close()
      throw e
    }
    val id = nextId++
    documents[id] = renderer
    return mapOf("id" to id, "widths" to widths, "heights" to heights)
  }

  private fun render(id: Int, page: Int, width: Int, height: Int): ByteArray {
    val renderer = documents[id] ?: throw PdfError("invalid", "Document $id is closed")
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    try {
      bitmap.eraseColor(Color.WHITE)
      renderer.openPage(page - 1).use {
        if (supportsPasswords) {
          val params = RenderParams.Builder(PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            .setRenderFlags(
              RenderParams.FLAG_RENDER_TEXT_ANNOTATIONS or RenderParams.FLAG_RENDER_HIGHLIGHT_ANNOTATIONS,
            )
            .build()
          it.render(bitmap, null, null, params)
        } else {
          it.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        }
      }
      val output = ByteArrayOutputStream(width * height / 4)
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
      return output.toByteArray()
    } finally {
      bitmap.recycle()
    }
  }
}
