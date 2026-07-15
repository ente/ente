package io.ente.photos

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeChannels.register(this, flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
    }

    @Deprecated("Kept for Android's IntentSender result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        NativeChannels.onActivityResult(requestCode, resultCode)
    }

    override fun onDestroy() {
        NativeChannels.unregister(this)
        super.onDestroy()
    }
}
