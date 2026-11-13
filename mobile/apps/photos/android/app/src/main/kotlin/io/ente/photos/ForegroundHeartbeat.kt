package io.ente.photos

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread

class ForegroundHeartbeat(private val context: Context) {
    private val handler by lazy {
        val thread = HandlerThread("ForegroundHeartbeat")
        thread.start()
        Handler(thread.looper)
    }
    private val preferences by lazy {
        context.getSharedPreferences(
            EnteApplication.FLUTTER_SHARED_PREFERENCES,
            Context.MODE_PRIVATE
        )
    }
    private var isRunning = false
    private val heartbeat =
        object : Runnable {
            override fun run() {
                if (!isRunning) {
                    return
                }
                writeNativeHeartbeat()
                handler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }

    fun start() {
        handler.post {
            if (isRunning) {
                return@post
            }
            isRunning = true
            heartbeat.run()
        }
    }

    fun stop() {
        handler.post {
            isRunning = false
            handler.removeCallbacks(heartbeat)
        }
    }

    private fun writeNativeHeartbeat() {
        preferences.edit()
            .putLong(
                NATIVE_FOREGROUND_HEARTBEAT_KEY,
                System.currentTimeMillis() * 1000L
            )
            .apply()
    }

    companion object {
        private const val NATIVE_FOREGROUND_HEARTBEAT_KEY = "flutter.native_fg_task_hb_time"
        private const val HEARTBEAT_INTERVAL_MS = 1000L

        fun install(application: Application) {
            val heartbeat = ForegroundHeartbeat(application)
            application.registerActivityLifecycleCallbacks(
                object : Application.ActivityLifecycleCallbacks {
                    private var startedActivities = 0

                    override fun onActivityPreCreated(
                        activity: Activity,
                        savedInstanceState: Bundle?
                    ) {
                        heartbeat.start()
                    }

                    override fun onActivityCreated(
                        activity: Activity,
                        savedInstanceState: Bundle?
                    ) {
                        heartbeat.start()
                    }

                    override fun onActivityStarted(activity: Activity) {
                        startedActivities++
                        heartbeat.start()
                    }

                    override fun onActivityResumed(activity: Activity) {}

                    override fun onActivityPaused(activity: Activity) {}

                    override fun onActivityStopped(activity: Activity) {
                        startedActivities--
                        if (startedActivities == 0) {
                            heartbeat.stop()
                        }
                    }

                    override fun onActivitySaveInstanceState(
                        activity: Activity,
                        outState: Bundle
                    ) {}

                    override fun onActivityDestroyed(activity: Activity) {
                        if (startedActivities == 0) {
                            heartbeat.stop()
                        }
                    }
                }
            )
        }
    }
}
