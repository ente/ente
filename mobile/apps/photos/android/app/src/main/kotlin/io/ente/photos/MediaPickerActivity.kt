package io.ente.photos

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MediaPickerActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        normalizePickerIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        normalizePickerIntent(intent)
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun normalizePickerIntent(intent: Intent?) {
        if (intent?.action == ACTION_PICK_IMAGES) {
            intent.action = Intent.ACTION_PICK
        }
    }

    private companion object {
        private const val ACTION_PICK_IMAGES = "android.provider.action.PICK_IMAGES"
    }
}
