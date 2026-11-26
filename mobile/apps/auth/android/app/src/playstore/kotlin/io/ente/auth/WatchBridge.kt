package io.ente.auth

import android.os.Build
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import io.ente.auth.watch.PhoneCompanion
import io.ente.auth.watch.Snapshot
import io.ente.auth.watch.WatchException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal object WatchBridge {
    fun register(activity: MainActivity, engine: FlutterEngine) {
        if (Build.VERSION.SDK_INT < 26) return
        val owner = PhoneCompanion(activity.applicationContext)
        val messenger = engine.dartExecutor.binaryMessenger
        val methods = MethodChannel(messenger, "io.ente.auth/watch").also { channel ->
            channel.setMethodCallHandler { call, result ->
                val complete: (Result<PhoneCompanion.State>) -> Unit = { outcome ->
                    outcome.fold({ result.success(it.asMap()) }, { result.fail(it) })
                }
                try {
                    when (call.method) {
                        "state" -> owner.readState(complete)
                        "approve" -> owner.approve(call.required("enrollmentID", "wrongEnrollment"), complete)
                        "publish" -> owner.publish(
                            Snapshot.decode(call.required("snapshot", "invalidSnapshot")),
                            call.required("enrollmentID", "wrongEnrollment"),
                            call.required("vaultEpoch", "staleVault"), complete)
                        "disable" -> owner.disable(call.required("enrollmentID", "wrongEnrollment"), complete)
                        "clear" -> owner.clear(complete)
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.fail(error) }
            }
        }
        val events = EventChannel(messenger, "io.ente.auth/watch/state").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    owner.onChange = { state -> sink.success(state.asMap()) }
                }
                override fun onCancel(arguments: Any?) {
                    owner.onChange = null
                }
            })
        }
        activity.lifecycle.addObserver(LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> owner.setForeground(true)
                Lifecycle.Event.ON_PAUSE -> owner.setForeground(false)
                Lifecycle.Event.ON_DESTROY -> {
                    methods.setMethodCallHandler(null)
                    events.setStreamHandler(null)
                    owner.close()
                }
                else -> Unit
            }
        })
    }
}

private fun PhoneCompanion.State.asMap(): Map<String, String?> = mapOf(
    "phase" to phase.name, "enrollmentID" to enrollmentID, "requestID" to requestID, "vaultEpoch" to vaultEpoch)

private fun <T> MethodCall.required(name: String, error: String): T =
    argument<T>(name) ?: throw WatchException(error)

private fun MethodChannel.Result.fail(failure: Throwable) {
    error((failure as? WatchException)?.code ?: "watchUnavailable", "Could not update the watch.", null)
}
