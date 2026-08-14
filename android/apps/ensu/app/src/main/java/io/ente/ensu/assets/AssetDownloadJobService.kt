package io.ente.ensu.assets

import android.app.Notification
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class AssetDownloadJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        synchronized(lock) {
            if (cancellations.isEmpty()) return false
            runningJob = this
            runningParams = params
        }
        setNotification(
            params,
            NOTIFICATION_ID,
            buildNotification(this, 0, true),
            JOB_END_NOTIFICATION_POLICY_REMOVE
        )
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        val callbacks = synchronized(lock) {
            if (runningParams !== params) return false
            runningJob = null
            runningParams = null
            val callbacks = cancellations.values.toList()
            cancellations.clear()
            callbacks
        }
        callbacks.forEach { it() }
        return false
    }

    companion object {
        private const val TAG = "AssetDownloadJob"
        private const val CHANNEL_ID = "asset-download"
        private const val NOTIFICATION_ID = 1
        private const val JOB_ID = 1
        private const val NOTIFY_INTERVAL_MS = 1000L

        private val lock = Any()
        private val cancellations = mutableMapOf<Long, () -> Unit>()
        private lateinit var appContext: Context
        private var nextId = 0L
        private var lastNotifyMs = 0L
        private var runningJob: AssetDownloadJobService? = null
        private var runningParams: JobParameters? = null

        fun attach(context: Context) {
            appContext = context.applicationContext
        }

        fun begin(onCancelled: () -> Unit): Long {
            val (id, first) = synchronized(lock) {
                val id = nextId++
                val first = cancellations.isEmpty()
                cancellations[id] = onCancelled
                if (first) lastNotifyMs = 0L
                id to first
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return id
            if (!first) return id
            val scheduler = appContext.getSystemService(JobScheduler::class.java)
            if (scheduler == null) {
                Log.w(TAG, "JobScheduler unavailable")
                return id
            }
            val job = JobInfo.Builder(JOB_ID, ComponentName(appContext, AssetDownloadJobService::class.java))
                .setUserInitiated(true)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .build()
            val result = runCatching { scheduler.schedule(job) }.getOrElse { error ->
                Log.w(TAG, "Download job schedule failed", error)
                return id
            }
            if (result != JobScheduler.RESULT_SUCCESS) {
                Log.w(TAG, "Download job not scheduled")
            }
            return id
        }

        fun update(id: Long, percent: Int, indeterminate: Boolean) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
            val job: AssetDownloadJobService
            val params: JobParameters
            val shownPercent: Int
            val shownIndeterminate: Boolean
            synchronized(lock) {
                if (id !in cancellations) return
                job = runningJob ?: return
                params = runningParams ?: return
                val now = SystemClock.elapsedRealtime()
                if (now - lastNotifyMs < NOTIFY_INTERVAL_MS) return
                lastNotifyMs = now
                shownPercent = if (cancellations.size == 1) percent else 0
                shownIndeterminate = cancellations.size != 1 || indeterminate
            }
            job.setNotification(
                params,
                NOTIFICATION_ID,
                buildNotification(appContext, shownPercent, shownIndeterminate),
                JOB_END_NOTIFICATION_POLICY_REMOVE
            )
        }

        fun end(id: Long) {
            val state = synchronized(lock) {
                if (cancellations.remove(id) == null) return
                if (cancellations.isNotEmpty()) return
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
                val state = runningJob to runningParams
                runningJob = null
                runningParams = null
                state
            }
            val (job, params) = state
            if (job != null && params != null) {
                job.jobFinished(params, false)
            }
        }

        private fun buildNotification(
            context: Context,
            percent: Int,
            indeterminate: Boolean
        ): Notification {
            NotificationManagerCompat.from(context).createNotificationChannel(
                NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                    .setName("Asset downloads")
                    .build()
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Downloading assets")
                .setProgress(100, percent, indeterminate)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
        }
    }
}
