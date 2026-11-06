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
    private var leaseStartId = 0
    private val coordinator
        get() = (application as EnsuApplication).backgroundGeneration

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestedLease = intent?.getStringExtra(BackgroundGeneration.LEASE)
        if (intent?.action == CANCEL) {
            requestedLease?.let(coordinator::cancelLease)
            if (lease == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (requestedLease == null || requestedLease != coordinator.lease) {
            if (lease == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (!updateForeground(requestedLease)) {
            if (lease != requestedLease) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (lease != requestedLease) {
            lease = requestedLease
            leaseStartId = startId
        }
        return START_NOT_STICKY
    }

    private fun updateForeground(id: String): Boolean {
        if (id != coordinator.lease) return false
        val notification = coordinator.progressNotification(id)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    BackgroundGeneration.PROGRESS_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE,
                )
            } else startForeground(BackgroundGeneration.PROGRESS_ID, notification)
            coordinator.renewLease(id) { updateForeground(id) }
        } catch (error: RuntimeException) {
            if (lease != id) coordinator.serviceUnavailable(id, error)
            return false
        }
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ expire() }, BackgroundGeneration.TIMEOUT_MS)
        return true
    }

    private fun expire() {
        val id = lease
        if (id != null && coordinator.isForeground && updateForeground(id)) return
        id?.let(coordinator::expire)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onTimeout(startId: Int) {
        if (startId >= leaseStartId) expire()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        if (startId >= leaseStartId) expire()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        lease?.let(coordinator::expire)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
