package io.ente.photos.platform.flutter

import android.graphics.Point
import android.graphics.RectF
import android.view.Surface
import io.ente.photos.platform.wallpaper.Destination
import io.ente.photos.platform.wallpaper.WallpaperSession
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture

@android.annotation.TargetApi(24)
open class WallpaperActivity : FlutterActivity() {
    private lateinit var session: WallpaperSession
    private lateinit var channel: MethodChannel

    override fun getDartEntrypointFunctionName() = "wallpaperMain"

    override fun getInitialRoute() = "/"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val size = Point()
        @Suppress("DEPRECATION")
        val display = windowManager.defaultDisplay
        @Suppress("DEPRECATION")
        display.getRealSize(size)
        if (display.rotation == Surface.ROTATION_90 || display.rotation == Surface.ROTATION_270) {
            size.set(size.y, size.x)
        }
        session = WallpaperSession(this, intent.data, size)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.ente.photos.platform/wallpaper")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> reply(session.preview().thenApply { bytes ->
                    mapOf("bytes" to bytes, "width" to size.x, "height" to size.y)
                }, result)
                "apply" -> {
                    val region = call.argument<List<Double>>("region")!!
                    val destination = Destination.valueOf(call.argument<String>("destination")!!.uppercase())
                    val crop = RectF(region[0].toFloat(), region[1].toFloat(), region[2].toFloat(), region[3].toFloat())
                    reply(session.apply(crop, destination).thenRun {
                        runOnUiThread { setResult(RESULT_OK) }
                    }, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun reply(task: CompletableFuture<*>, result: MethodChannel.Result) {
        task.whenComplete { value, error ->
            runOnUiThread {
                if (!isDestroyed) {
                    if (error == null) result.success(value)
                    else result.error(if (error.cause is UnsupportedOperationException) "unavailable" else "wallpaper_failed", error.message, null)
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel.setMethodCallHandler(null)
        session.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
