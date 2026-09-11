package io.ente.photos

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin

class WallpaperActivity : io.ente.photos.platform.flutter.WallpaperActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SharedPreferencesPlugin())
    }
}
