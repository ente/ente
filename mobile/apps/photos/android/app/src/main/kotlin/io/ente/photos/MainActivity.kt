package io.ente.photos

import android.content.Intent
import android.os.Bundle
import io.ente.background.BackgroundManagerPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileDescriptor
import java.io.PrintWriter

class MainActivity : FlutterFragmentActivity() {
    private lateinit var finishTaskChannel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        BackgroundManagerPlugin.onForeground()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        finishTaskChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.ente/finishTask",
        )
        finishTaskChannel.setMethodCallHandler { call, result ->
            if (call.method == "finishAndRemoveTask") {
                finishAndRemoveTask()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun dump(
        prefix: String,
        fd: FileDescriptor?,
        writer: PrintWriter,
        args: Array<out String>?,
    ) {
        if (args?.singleOrNull() == "--ente-logs") {
            AdbDiagnostics.dumpLogs(this, writer)
        } else {
            super.dump(prefix, fd, writer, args)
        }
    }
}
