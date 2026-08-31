package io.ente.photos

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.util.Log
import androidx.core.app.NotificationCompat
import dev.fluttercommunity.workmanager.TaskDebugInfo
import dev.fluttercommunity.workmanager.TaskResult
import dev.fluttercommunity.workmanager.WorkmanagerDebug
import dev.fluttercommunity.workmanager.pigeon.TaskStatus
import org.json.JSONObject
import kotlin.random.Random

class EnteApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    WorkmanagerDebug.setCurrent(InternalUserWorkmanagerDebugHandler())
    ForegroundHeartbeat.install(this)
  }

  companion object {
    const val FLUTTER_SHARED_PREFERENCES = "FlutterSharedPreferences"
    const val REMOTE_FLAGS_KEY = "flutter.remote_flags"
    const val INTERNAL_USER_DISABLED_KEY = "flutter.ls.internal_user_disabled"
    const val BG_DEBUG_NOTIFICATIONS_ENABLED_KEY =
      "flutter.ls.bg_debug_notifications_enabled"
    const val TAG = "EnteApplication"
  }
}

private class InternalUserWorkmanagerDebugHandler : WorkmanagerDebug() {
  override fun onTaskStatusUpdate(
    context: Context,
    taskInfo: TaskDebugInfo,
    status: TaskStatus,
    result: TaskResult?,
  ) {
    if (!shouldEnableWorkmanagerDebugNotifications(context)) {
      return
    }

    val notification = formatNotification(taskInfo, status, result) ?: return
    postNotification(context, notification.first, notification.second)
  }

  override fun onExceptionEncountered(
    context: Context,
    taskInfo: TaskDebugInfo?,
    exception: Throwable,
  ) {
    if (!shouldEnableWorkmanagerDebugNotifications(context)) {
      return
    }
    val taskName = taskInfo?.taskName ?: "unknown"
    postNotification(
      context,
      "Failed",
      "$taskName\n${exception.message ?: "Unknown exception"}",
    )
  }

  private fun shouldEnableWorkmanagerDebugNotifications(context: Context): Boolean {
    val prefs =
      context.getSharedPreferences(
        EnteApplication.FLUTTER_SHARED_PREFERENCES,
        Context.MODE_PRIVATE,
      )
    if (prefs.getBoolean(EnteApplication.INTERNAL_USER_DISABLED_KEY, false)) {
      return false
    }
    if (!prefs.getBoolean(EnteApplication.BG_DEBUG_NOTIFICATIONS_ENABLED_KEY, false)) {
      return false
    }

    return isInternalUser(prefs.getString(EnteApplication.REMOTE_FLAGS_KEY, null))
  }

  private fun isInternalUser(remoteFlags: String?): Boolean {
    if (remoteFlags.isNullOrBlank()) {
      return false
    }

    return runCatching {
      JSONObject(remoteFlags).optBoolean("internalUser", false)
    }.getOrElse {
      Log.w(
        EnteApplication.TAG,
        "Failed to parse remote flags for Workmanager debug handler",
        it,
      )
      false
    }
  }

  private fun formatNotification(
    taskInfo: TaskDebugInfo,
    status: TaskStatus,
    result: TaskResult?,
  ): Pair<String, String>? {
    return when (status) {
      TaskStatus.SCHEDULED -> "Scheduled" to taskInfo.taskName
      TaskStatus.STARTED -> "Started" to taskInfo.taskName
      TaskStatus.RETRYING -> "Retrying" to taskInfo.taskName
      TaskStatus.RESCHEDULED -> "Rescheduled" to taskInfo.taskName
      TaskStatus.COMPLETED -> {
        val duration = (result?.duration ?: 0) / 1000
        "Success ${duration}s" to taskInfo.taskName
      }
      TaskStatus.FAILED -> {
        val duration = (result?.duration ?: 0) / 1000
        val error = result?.error ?: "Unknown"
        "Failed ${duration}s" to "${taskInfo.taskName}\n$error"
      }
      TaskStatus.CANCELLED -> "Cancelled" to taskInfo.taskName
    }
  }

  private fun postNotification(
    context: Context,
    title: String,
    content: String,
  ) {
    val notificationManager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    ensureNotificationChannel(notificationManager)

    val notification =
      NotificationCompat.Builder(context, CHANNEL_ID)
        .setContentTitle(title)
        .setContentText(content)
        .setStyle(NotificationCompat.BigTextStyle().bigText(content))
        .setSmallIcon(android.R.drawable.stat_notify_sync)
        .setPriority(NotificationCompat.PRIORITY_MIN)
        .setGroup(GROUP_KEY)
        .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
        .setSilent(true)
        .setOnlyAlertOnce(true)
        .build()

    notificationManager.notify(Random.nextInt(), notification)
    notificationManager.notify(SUMMARY_NOTIFICATION_ID, buildSummaryNotification(context))
  }

  private fun ensureNotificationChannel(notificationManager: NotificationManager) {
    val channel =
      NotificationChannel(
        CHANNEL_ID,
        CHANNEL_NAME,
        NotificationManager.IMPORTANCE_MIN,
      ).apply {
        setSound(null, null)
        enableVibration(false)
        vibrationPattern = longArrayOf(0L)
        setShowBadge(false)
      }
    notificationManager.createNotificationChannel(channel)
  }

  private fun buildSummaryNotification(context: Context) =
    NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle("Workmanager Debug")
      .setContentText("Background task updates")
      .setSmallIcon(android.R.drawable.stat_notify_sync)
      .setPriority(NotificationCompat.PRIORITY_MIN)
      .setGroup(GROUP_KEY)
      .setGroupSummary(true)
      .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
      .setSilent(true)
      .setOnlyAlertOnce(true)
      .build()

  private companion object {
    const val CHANNEL_ID = "io.ente.photos.workmanager.debug"
    const val CHANNEL_NAME = "Workmanager Debug"
    const val GROUP_KEY = "io.ente.photos.workmanager.debug.group"
    const val SUMMARY_NOTIFICATION_ID = 424242
  }
}
