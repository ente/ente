package io.ente.photos

import io.flutter.embedding.engine.FlutterEngine

object NativeChannels {
    fun register(activity: MainActivity, flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MediaStoreChannel(activity).register(messenger)
    }
}
