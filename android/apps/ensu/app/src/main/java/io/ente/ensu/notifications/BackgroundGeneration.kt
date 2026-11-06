package io.ente.ensu.notifications

import android.app.Activity
import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.ente.ensu.EnsuApplication
import io.ente.ensu.MainActivity
import io.ente.ensu.R
import io.ente.ensu.bindings.stripHiddenPartsText
import io.ente.ensu.logging.LogLevel
import java.util.UUID

class BackgroundGeneration(private val app: EnsuApplication) :
    Application.ActivityLifecycleCallbacks {
    companion object {
        const val PROGRESS_CHANNEL = "response_generation"
        const val RESPONSE_CHANNEL = "response_updates"
        const val TIMEOUT_MS = 170_000L
        const val PROGRESS_ID = 2001
        const val SESSION = "response_session"
        const val MESSAGE = "response_message"
        const val LEASE = "generation_lease"
    }

    private val visibleActivities = mutableSetOf<Activity>()
    private val resumedActivities = mutableSetOf<Activity>()
    @Volatile
    var isForeground = false
        private set

    private var refreshLease: (() -> Unit)? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val lifecycle = ResponseNotificationLifecycle()
    private var cancel: (() -> Unit)? = null
    var lease: String? = null
        private set

    private val manager = app.getSystemService(NotificationManager::class.java)

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannels(
                listOf(
                    NotificationChannel(
                            PROGRESS_CHANNEL,
                            "Response in progress",
                            NotificationManager.IMPORTANCE_LOW,
                        )
                        .apply {
                            setSound(null, null)
                            enableVibration(false)
                        },
                    NotificationChannel(
                            RESPONSE_CHANNEL,
                            "Response updates",
                            NotificationManager.IMPORTANCE_DEFAULT,
                        )
                        .apply { enableVibration(true) },
                )
            )
        }
    }

    fun begin(id: Long, session: String, parent: String, query: String, onCancel: () -> Unit) {
        releaseLease()
        lifecycle.begin(ResponseNotificationAttempt(id, session, parent, query))
        cancel = onCancel
        if (resumedActivities.isEmpty()) startLease()
    }

    fun finish(id: Long) {
        lifecycle.resolve(id)?.let(::interrupted)
        if (!lifecycle.clear(id)) return
        cancel = null
        releaseLease()
    }

    fun cancelAttempt(id: Long) {
        if (lifecycle.resolve(id) == null) return
        cancel = null
    }

    fun cancelLease(expectedLease: String) {
        if (lease != expectedLease) return
        val cancellation = cancel
        lifecycle.current?.id?.let(::cancelAttempt)
        cancellation?.invoke()
    }

    fun expire(expectedLease: String) {
        if (lease != expectedLease) return
        if (isForeground) {
            releaseLease()
            return
        }
        val cancellation = cancel
        lifecycle.current?.id?.let(::finish)
        cancellation?.invoke()
    }

    fun completed(id: Long, message: String, text: String) {
        val attempt = lifecycle.resolve(id) ?: return
        val preview = responsePreview(stripHiddenPartsText(text))
        if (preview.isBlank()) return
        postNotice(
            tag = "ensu.response.$message",
            title = responseNotificationTitle(attempt.query),
            body = preview,
            session = attempt.session,
            message = message,
        )
    }

    private fun interrupted(attempt: ResponseNotificationAttempt) {
        postNotice(
            tag = "ensu.interrupted.${attempt.parent}",
            title = "Response generation was interrupted",
            body = "Open Ensu to retry.",
            session = attempt.session,
            message = attempt.parent,
        )
    }

    private fun postNotice(
        tag: String,
        title: String,
        body: String,
        session: String,
        message: String,
    ) {
        if (isForeground || !app.notificationPermissions.enabled()) return
        val notification =
            NotificationCompat.Builder(app, RESPONSE_CHANNEL)
                .setSmallIcon(R.drawable.ic_response_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(openChat(session, message))
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .apply {
                    if (Build.VERSION.SDK_INT < 26) {
                        setDefaults(Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE)
                    }
                }
                .build()
        runCatching { manager.notify(tag, 0, notification) }
            .onFailure { error ->
                app.logRepository.log(
                    LogLevel.Warning,
                    "Could not post response notification",
                    tag = "Generation",
                    throwable = error,
                )
            }
    }

    private fun clearResponseNotifications() {
        manager.activeNotifications
            .filter {
                it.tag?.startsWith("ensu.response.") == true ||
                    it.tag?.startsWith("ensu.interrupted.") == true ||
                    (Build.VERSION.SDK_INT >= 26 && it.notification.channelId == RESPONSE_CHANNEL)
            }
            .forEach { manager.cancel(it.tag, it.id) }
    }

    fun progressNotification(expectedLease: String): Notification {
        val stop =
            Intent(app, GenerationService::class.java)
                .setAction(GenerationService.CANCEL)
                .putExtra(LEASE, expectedLease)
        val cancelIntent =
            PendingIntent.getService(
                app,
                expectedLease.hashCode(),
                stop,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return NotificationCompat.Builder(app, PROGRESS_CHANNEL)
            .setSmallIcon(R.drawable.ic_response_notification)
            .setContentTitle("Ensu")
            .setContentText("Generating response…")
            .setContentIntent(openChat(lifecycle.current?.session, null))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(0, "Cancel", cancelIntent)
            .build()
    }

    private fun openChat(session: String?, message: String?): PendingIntent {
        val intent =
            Intent(app, MainActivity::class.java)
                .setAction("io.ente.ensu.OPEN_RESPONSE.$message")
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(SESSION, session)
                .putExtra(MESSAGE, message)
        return PendingIntent.getActivity(
            app,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startLease() {
        if (lifecycle.current == null || lease != null) return
        val id = UUID.randomUUID().toString()
        lease = id
        try {
            val lock =
                app.getSystemService(PowerManager::class.java)
                    .newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "${app.packageName}:ResponseGeneration",
                    )
            lock.setReferenceCounted(false)
            wakeLock = lock
            lock.acquire(TIMEOUT_MS)
            val intent = Intent(app, GenerationService::class.java).putExtra(LEASE, id)
            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent)
            else app.startService(intent)
        } catch (error: RuntimeException) {
            serviceUnavailable(id, error)
        }
    }

    fun renewLease(expectedLease: String, refresh: () -> Unit) {
        if (lease != expectedLease) return
        wakeLock?.acquire(TIMEOUT_MS)
        refreshLease = refresh
    }

    fun serviceUnavailable(id: String, error: RuntimeException) {
        expire(id)
        app.logRepository.log(
            LogLevel.Warning,
            "Background generation service unavailable",
            tag = "Generation",
            throwable = error,
        )
    }

    private fun releaseLease() {
        lease = null
        refreshLease = null
        val lock = wakeLock
        wakeLock = null
        if (lock?.isHeld == true) lock.release()
        app.stopService(Intent(app, GenerationService::class.java))
        manager.cancel(PROGRESS_ID)
    }

    override fun onActivityStarted(activity: Activity) {
        visibleActivities.add(activity)
        isForeground = true
        clearResponseNotifications()
        app.notificationPermissions.refresh()
    }

    override fun onActivityStopped(activity: Activity) {
        visibleActivities.remove(activity)
        if (visibleActivities.isEmpty() && !activity.isChangingConfigurations) {
            isForeground = false
            if (lease == null) startLease() else refreshLease?.invoke()
        }
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit

    override fun onActivityResumed(activity: Activity) {
        resumedActivities.add(activity)
        releaseLease()
    }

    override fun onActivityPaused(activity: Activity) {
        resumedActivities.remove(activity)
        if (resumedActivities.isEmpty() && !activity.isChangingConfigurations) startLease()
    }

    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) {
        visibleActivities.remove(activity)
        resumedActivities.remove(activity)
    }
}
