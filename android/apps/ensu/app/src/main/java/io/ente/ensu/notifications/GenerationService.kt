package io.ente.ensu.notifications

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.ente.ensu.EnsuApplication

class GenerationService : Service() {
    companion object {
        const val CANCEL = "io.ente.ensu.CANCEL_GENERATION"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lease: String? = null
    private var latestStartId = 0
    private val coordinator
        get() = (application as EnsuApplication).backgroundGeneration

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestedLease = intent?.getStringExtra(BackgroundGeneration.LEASE)
        if (intent?.action == CANCEL) {
            requestedLease?.let(coordinator::cancelLease)
            if (lease == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (
            requestedLease == null ||
                requestedLease != coordinator.lease ||
                coordinator.isForeground
        ) {
            if (lease == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        latestStartId = startId
        val notification = coordinator.progressNotification(requestedLease)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    BackgroundGeneration.PROGRESS_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
                )
            } else startForeground(BackgroundGeneration.PROGRESS_ID, notification)
        } catch (error: RuntimeException) {
            coordinator.serviceUnavailable(requestedLease, error)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (lease != requestedLease) {
            lease = requestedLease
            handler.removeCallbacksAndMessages(null)
            handler.postDelayed({ expire() }, BackgroundGeneration.TIMEOUT_MS)
        }
        return START_NOT_STICKY
    }

    private fun expire() {
        lease?.let(coordinator::expire)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTimeout(startId: Int) {
        if (startId == latestStartId) expire()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        if (startId == latestStartId) expire()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        lease?.let(coordinator::expire)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
