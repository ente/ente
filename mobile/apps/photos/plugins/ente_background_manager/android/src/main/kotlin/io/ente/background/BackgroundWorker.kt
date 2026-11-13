package io.ente.background

import android.content.Context
import android.os.SystemClock
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture

class BackgroundWorker(context: Context, parameters: WorkerParameters) :
    ListenableWorker(context, parameters) {
    override fun startWork(): ListenableFuture<Result> {
        val startedAt = SystemClock.elapsedRealtime()
        return CallbackToFutureAdapter.getFuture { completer ->
            BackgroundRuntime.start(this, startedAt) { successful ->
                if (!isStopped) {
                    completer.set(if (successful) Result.success() else Result.failure())
                }
            }
            id.toString()
        }
    }

    override fun onStopped() {
        BackgroundRuntime.nativeStop(this)
    }
}
