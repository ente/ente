package io.ente.auth

import android.app.ActivityManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Match the system's secure task background through the status bar.
            setTaskDescription(
                ActivityManager.TaskDescription.Builder()
                    .setBackgroundColor(Color.WHITE)
                    .setStatusBarColor(Color.WHITE)
                    .build(),
            )
        }
    }
}
