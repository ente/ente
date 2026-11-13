package io.ente.install_source

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.plugin.common.MethodChannel

class InstallSourceProvider(private val context: Context) {
    private val store = InstallSourceEventStore(context)
    private val pendingCallbacks = mutableListOf<(InstallSource?) -> Unit>()

    private var cachedSource: InstallSource? = null
    private var isFetching = false

    fun hasInstallSource(result: MethodChannel.Result) {
        getInstallSource { source ->
            result.success(source?.hasNonOrganicReferrer == true)
        }
    }

    fun autoAttributeSource(isSignUp: Boolean, result: MethodChannel.Result) {
        store.autoAttributeSource(isSignUp)
        result.success(null)
    }

    fun getPendingEvents(result: MethodChannel.Result) {
        getInstallSource { source ->
            result.success(source?.let { store.pendingEventJsons(it) }.orEmpty())
        }
    }

    fun markEventSent(event: String?, result: MethodChannel.Result) {
        store.markEventSent(event.orEmpty())
        result.success(null)
    }

    @Synchronized
    private fun getInstallSource(callback: (InstallSource?) -> Unit) {
        val source = cachedSource ?: store.sourceFromState()
        if (source != null) {
            cachedSource = source
            callback(source)
            return
        }
        if (!isFreshInstall()) {
            val emptySource = InstallSource(emptyMap())
            cachedSource = emptySource
            store.saveSource(emptySource)
            callback(emptySource)
            return
        }

        pendingCallbacks.add(callback)
        if (isFetching) {
            return
        }
        isFetching = true
        fetchInstallSource { fetchedSource ->
            val callbacks = synchronized(this) {
                if (fetchedSource != null) {
                    cachedSource = fetchedSource
                    store.saveSource(fetchedSource)
                }
                isFetching = false
                pendingCallbacks.toList().also {
                    pendingCallbacks.clear()
                }
            }
            callbacks.forEach { it(fetchedSource) }
        }
    }

    private fun fetchInstallSource(callback: (InstallSource?) -> Unit) {
        val client = InstallReferrerClient.newBuilder(context).build()
        val completionLock = Any()
        var completed = false
        val handler = Handler(Looper.getMainLooper())
        lateinit var timeoutRunnable: Runnable

        fun complete(source: InstallSource?) {
            synchronized(completionLock) {
                if (completed) {
                    return
                }
                completed = true
            }
            handler.removeCallbacks(timeoutRunnable)
            try {
                client.endConnection()
            } catch (_: Exception) {
            }
            handler.post { callback(source) }
        }

        timeoutRunnable = Runnable {
            complete(null)
        }
        handler.postDelayed(
            timeoutRunnable,
            INSTALL_REFERRER_TIMEOUT_MS,
        )

        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    when (responseCode) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> {
                            try {
                                val details = client.installReferrer
                                complete(
                                    store.playSource(
                                        referrer = details.installReferrer,
                                    )
                                )
                            } catch (_: Exception) {
                                complete(null)
                            }
                        }

                        else -> complete(null)
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    complete(null)
                }
            })
        } catch (_: Exception) {
            complete(null)
        }
    }

    private fun isFreshInstall(): Boolean {
        val packageInfo = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(0L),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
        } catch (_: Exception) {
            return false
        }
        val installUpdateDeltaMs = packageInfo.lastUpdateTime - packageInfo.firstInstallTime
        return installUpdateDeltaMs in 0L..FRESH_INSTALL_TOLERANCE_MS
    }

    private companion object {
        const val INSTALL_REFERRER_TIMEOUT_MS = 2000L
        const val FRESH_INSTALL_TOLERANCE_MS = 2 * 60 * 1000L
    }
}
