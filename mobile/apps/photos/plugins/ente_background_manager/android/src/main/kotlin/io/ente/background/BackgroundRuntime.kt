package io.ente.background

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject

internal object BackgroundRuntime {
    private const val TAG = "EnteBackgroundManager"
    private const val PREFERENCES = "ente_background_manager"
    private const val CONFIGURATION = "configuration"
    private const val TASK_DATA = "task"
    private const val WORK_TAG = "io.ente.background"
    private const val IDENTIFIER_TAG_PREFIX = "io.ente.background.task:"
    private const val PREEMPTION_TIMEOUT_MS = 30_000L
    private val main = Handler(Looper.getMainLooper())
    private val scheduler = Executors.newSingleThreadExecutor()
    private val observers = LinkedHashSet<BackgroundManagerPlugin>()
    private val startedActivities = HashSet<Activity>()
    private val startingActivities = HashSet<Activity>()
    private var application: Application? = null
    private var isAllowed: () -> Boolean = { false }
    private var isForeground = false
    private var active: Run? = null
    private var pending: Pending? = null
    var createEngine: (Context) -> FlutterEngine = { FlutterEngine(it) }
    var findCallback: (Long) -> FlutterCallbackInformation? =
        FlutterCallbackInformation::lookupCallbackInformation

    private class Run(
        val worker: BackgroundWorker,
        val configuration: TaskConfiguration,
        val startedAt: Long,
        val completion: (Boolean) -> Unit,
    ) {
        val invocation = UUID.randomUUID().toString()
        var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
        var ready = false
        var retiring = false
        var teardownFailure: Exception? = null
        var stopReason: String? = null
        var budgetTimer: Runnable? = null
        var foregroundTimer: Runnable? = null
        val stopResults = ArrayList<MethodChannel.Result>()
    }

    private class Pending(
        val worker: BackgroundWorker,
        val configuration: TaskConfiguration,
        val startedAt: Long,
        val completion: (Boolean) -> Unit,
    ) {
        var timer: Runnable? = null
    }

    fun install(app: Application, allowed: () -> Boolean) {
        isAllowed = allowed
        if (application != null) return
        application = app
        app.registerActivityLifecycleCallbacks(
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityPreCreated(activity: Activity, savedInstanceState: Bundle?) {
                    startingActivities.add(activity)
                    foreground()
                }

                override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                    startingActivities.add(activity)
                    foreground()
                }

                override fun onActivityStarted(activity: Activity) {
                    startingActivities.remove(activity)
                    startedActivities.add(activity)
                    foreground()
                }

                override fun onActivityResumed(activity: Activity) = foreground()

                override fun onActivityStopped(activity: Activity) {
                    startedActivities.remove(activity)
                    if (startedActivities.isEmpty() && startingActivities.isEmpty())
                        isForeground = false
                }

                override fun onActivityDestroyed(activity: Activity) {
                    startedActivities.remove(activity)
                    startingActivities.remove(activity)
                    if (startedActivities.isEmpty() && startingActivities.isEmpty())
                        isForeground = false
                }

                override fun onActivityPaused(activity: Activity) = Unit

                override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) =
                    Unit
            }
        )
    }

    fun attach(plugin: BackgroundManagerPlugin) {
        observers.add(plugin)
    }

    fun detach(plugin: BackgroundManagerPlugin) {
        observers.remove(plugin)
    }

    fun foreground() {
        isForeground = true
        skipPending("foreground")
        active?.let { stop(it, "foreground") }
    }

    fun requestStop(result: MethodChannel.Result? = null) {
        skipPending("requested")
        val run = active
        if (run == null) {
            result?.success(null)
            return
        }
        run.teardownFailure?.let {
            result?.error("teardown", it.message, null)
            return
        }
        if (result != null) run.stopResults.add(result)
        stop(run, "requested")
    }

    fun configure(arguments: Map<*, *>?, result: MethodChannel.Result) {
        val app = application
        if (app == null || arguments == null) {
            result.error("configuration", "Background manager was not installed at launch", null)
            return
        }
        val configurations: List<TaskConfiguration>
        val enabled: Boolean
        try {
            val callback = (arguments["callbackHandle"] as Number).toLong()
            configurations =
                (arguments["tasks"] as List<*>).map {
                    TaskConfiguration.decode(JSONObject(it as Map<*, *>), callback)
                }
            require(configurations.map { it.identifier }.toSet().size == configurations.size)
            enabled = arguments["enabled"] as Boolean
        } catch (exception: Exception) {
            result.error("configuration", exception.message, null)
            return
        }
        if (!enabled) requestStop()
        scheduler.execute {
            try {
                val preferences = app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                val previous = preferences.getString(CONFIGURATION, null)?.let(::JSONObject)
                val previousTasks = previous?.optJSONArray("tasks") ?: JSONArray()
                val json =
                    JSONObject()
                        .put("enabled", enabled)
                        .put(
                            "tasks",
                            JSONArray(configurations.map { JSONObject(it.encode()) }),
                        )
                check(preferences.edit().putString(CONFIGURATION, json.toString()).commit())
                val manager = WorkManager.getInstance(app)
                val selected =
                    if (enabled) configurations.map { it.identifier }.toSet() else emptySet()
                val existingIdentifiers =
                    manager
                        .getWorkInfosByTag(WORK_TAG)
                        .get()
                        .filterNot { it.state.isFinished }
                        .flatMap { it.tags }
                        .filter { it.startsWith(IDENTIFIER_TAG_PREFIX) }
                        .map { it.removePrefix(IDENTIFIER_TAG_PREFIX) }
                        .toMutableSet()
                for (index in 0 until previousTasks.length()) {
                    existingIdentifiers.add(
                        previousTasks.getJSONObject(index).getString("identifier")
                    )
                }
                val activeTask = FutureTask {
                    if (!enabled) requestStop()
                    active?.configuration?.identifier
                }
                main.post(activeTask)
                val activeIdentifier = activeTask.get()
                for (identifier in existingIdentifiers) {
                    if (identifier !in selected && identifier != activeIdentifier) {
                        manager.cancelUniqueWork(identifier).result.get()
                    }
                }
                if (enabled) {
                    for (configuration in configurations) {
                        val builder =
                            configuration.flexMs?.let {
                                PeriodicWorkRequest.Builder(
                                    BackgroundWorker::class.java,
                                    configuration.frequencyMs,
                                    TimeUnit.MILLISECONDS,
                                    it,
                                    TimeUnit.MILLISECONDS,
                                )
                            }
                                ?: PeriodicWorkRequest.Builder(
                                    BackgroundWorker::class.java,
                                    configuration.frequencyMs,
                                    TimeUnit.MILLISECONDS,
                                )
                        val request =
                            builder
                                .addTag(WORK_TAG)
                                .addTag(IDENTIFIER_TAG_PREFIX + configuration.identifier)
                                .setInitialDelay(
                                    configuration.initialDelayMs,
                                    TimeUnit.MILLISECONDS,
                                )
                                .setInputData(
                                    Data.Builder()
                                        .putString(TASK_DATA, configuration.encode())
                                        .build()
                                )
                                .setConstraints(
                                    Constraints.Builder()
                                        .setRequiredNetworkType(
                                            if (configuration.requiresNetwork) NetworkType.CONNECTED
                                            else NetworkType.NOT_REQUIRED
                                        )
                                        .setRequiresCharging(configuration.requiresCharging)
                                        .setRequiresDeviceIdle(configuration.requiresDeviceIdle)
                                        .build()
                                )
                                .build()
                        manager
                            .enqueueUniquePeriodicWork(
                                configuration.identifier,
                                ExistingPeriodicWorkPolicy.UPDATE,
                                request,
                            )
                            .result
                            .get()
                    }
                }
                main.post { result.success(null) }
            } catch (exception: Exception) {
                main.post { result.error("schedule", exception.message, null) }
            }
        }
    }

    fun scheduledTasks(result: MethodChannel.Result) {
        val app =
            application
                ?: run {
                    result.error(
                        "configuration",
                        "Background manager was not installed at launch",
                        null,
                    )
                    return
                }
        scheduler.execute {
            try {
                val json =
                    app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                        .getString(CONFIGURATION, null)
                        ?.let(::JSONObject)
                val tasks = json?.optJSONArray("tasks") ?: JSONArray()
                val manager = WorkManager.getInstance(app)
                val states =
                    (0 until tasks.length()).associate { index ->
                        val identifier = tasks.getJSONObject(index).getString("identifier")
                        identifier to
                            manager.getWorkInfosForUniqueWork(identifier).get().any {
                                !it.state.isFinished
                            }
                    }
                main.post { result.success(states) }
            } catch (exception: Exception) {
                main.post { result.error("schedule", exception.message, null) }
            }
        }
    }

    fun start(worker: BackgroundWorker, startedAt: Long, completion: (Boolean) -> Unit) {
        onMain {
            if (worker.isStopped) return@onMain
            val configuration =
                try {
                    TaskConfiguration.decode(
                        JSONObject(requireNotNull(worker.inputData.getString(TASK_DATA)))
                    )
                } catch (exception: Exception) {
                    report("unknown", "failed", "configuration", exception.message)
                    completion(false)
                    return@onMain
                }
            val enabled =
                try {
                    val saved =
                        application
                            ?.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                            ?.getString(CONFIGURATION, null)
                            ?.let(::JSONObject)
                    val tasks = saved?.optJSONArray("tasks") ?: JSONArray()
                    saved?.optBoolean("enabled") == true &&
                        isAllowed() &&
                        (0 until tasks.length()).any {
                            tasks.getJSONObject(it).getString("identifier") ==
                                configuration.identifier
                        }
                } catch (exception: Exception) {
                    report(configuration.identifier, "failed", "configuration", exception.message)
                    completion(false)
                    return@onMain
                }
            val occupant = active
            val preempts = occupant != null && canPreempt(occupant, configuration)
            val skip =
                when {
                    !enabled -> "disabled"
                    occupant != null && !preempts -> "busy"
                    isForeground -> "foreground"
                    else -> null
                }
            if (skip != null) {
                report(configuration.identifier, "skipped", skip)
                if (skip == "disabled") {
                    retireUnselectedSchedule(configuration.identifier)
                }
                completion(true)
                return@onMain
            }
            if (occupant != null) {
                preempt(occupant, Pending(worker, configuration, startedAt, completion))
                return@onMain
            }
            val run = Run(worker, configuration, startedAt, completion)
            active = run
            configuration.runBudgetMs?.let { budget ->
                run.budgetTimer =
                    Runnable { if (active === run) stop(run, "budget") }
                        .also {
                            main.postDelayed(it, (budget - elapsed(run)).coerceAtLeast(0))
                        }
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(worker.applicationContext)
                loader.ensureInitializationCompleteAsync(worker.applicationContext, null, main) {
                    if (active !== run || run.retiring) return@ensureInitializationCompleteAsync
                    if (run.worker.isStopped) {
                        retire(run, "stopped", "system")
                        return@ensureInitializationCompleteAsync
                    }
                    run.stopReason?.let {
                        retire(run, "stopped", it)
                        return@ensureInitializationCompleteAsync
                    }
                    try {
                        val callback =
                            requireNotNull(findCallback(configuration.callbackHandle)) {
                                "Background dispatcher is unavailable"
                            }
                        val engine = createEngine(worker.applicationContext)
                        run.engine = engine
                        val channel =
                            MethodChannel(
                                engine.dartExecutor.binaryMessenger,
                                "io.ente.background/worker",
                            )
                        run.channel = channel
                        channel.setMethodCallHandler { call, result ->
                            if (active !== run || run.retiring) {
                                result.success(null)
                            } else
                                when (call.method) {
                                    "ready" -> {
                                        if (run.ready) {
                                            result.error(
                                                "bootstrap",
                                                "Dispatcher already started",
                                                null,
                                            )
                                        } else {
                                            run.ready = true
                                            result.success(
                                                mapOf(
                                                    "invocation" to run.invocation,
                                                    "identifier" to configuration.identifier,
                                                    "elapsedMs" to elapsed(run),
                                                    "runBudgetMs" to configuration.runBudgetMs,
                                                    "stopReason" to run.stopReason,
                                                )
                                            )
                                        }
                                    }
                                    "complete" -> {
                                        val data = call.arguments as? Map<*, *>
                                        if (data?.get("invocation") != run.invocation) {
                                            result.error(
                                                "invocation",
                                                "Stale background completion",
                                                null,
                                            )
                                        } else {
                                            val outcome = data["outcome"] as? String
                                            if (
                                                outcome !in
                                                    setOf(
                                                        "completed",
                                                        "skipped",
                                                        "stopped",
                                                        "failed",
                                                    )
                                            ) {
                                                result.error(
                                                    "outcome",
                                                    "Unknown task outcome",
                                                    null,
                                                )
                                            } else {
                                                result.success(null)
                                                retire(
                                                    run,
                                                    outcome!!,
                                                    run.stopReason,
                                                    data["error"] as? String,
                                                )
                                            }
                                        }
                                    }
                                    else -> result.notImplemented()
                                }
                        }
                        engine.dartExecutor.executeDartCallback(
                            DartExecutor.DartCallback(
                                worker.applicationContext.assets,
                                loader.findAppBundlePath(),
                                callback,
                            )
                        )
                    } catch (exception: Exception) {
                        retire(run, "failed", "bootstrap", exception.message)
                    }
                }
            } catch (exception: Exception) {
                retire(run, "failed", "bootstrap", exception.message)
            }
        }
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == main.looper) action() else main.post { action() }
    }

    private fun canPreempt(occupant: Run, configuration: TaskConfiguration): Boolean =
        pending == null &&
            !isForeground &&
            occupant.teardownFailure == null &&
            occupant.configuration.kind == "refresh" &&
            configuration.kind == "processing"

    private fun preempt(occupant: Run, waiting: Pending) {
        pending = waiting
        waiting.timer =
            Runnable { if (pending === waiting) skipPending("busy") }
                .also { main.postDelayed(it, PREEMPTION_TIMEOUT_MS) }
        stop(occupant, "preempted")
    }

    private fun takePending(): Pending? {
        val waiting = pending ?: return null
        pending = null
        waiting.timer?.let(main::removeCallbacks)
        return waiting
    }

    private fun skipPending(reason: String) {
        val waiting = takePending() ?: return
        report(waiting.configuration.identifier, "skipped", reason)
        waiting.completion(true)
    }

    private fun resumePending() {
        val waiting = takePending() ?: return
        start(waiting.worker, waiting.startedAt, waiting.completion)
    }

    fun nativeStop(worker: BackgroundWorker) {
        main.post {
            pending
                ?.takeIf { it.worker === worker }
                ?.let {
                    takePending()
                    report(it.configuration.identifier, "stopped", "system")
                    it.completion(true)
                }
            active
                ?.takeIf { it.worker === worker }
                ?.let {
                    stop(it, "system")
                    val reason =
                        if (
                            Build.VERSION.SDK_INT >= 31 &&
                                worker.stopReason != WorkInfo.STOP_REASON_UNKNOWN
                        ) {
                            "system:${worker.stopReason}"
                        } else "system"
                    retire(it, "stopped", reason)
                }
        }
    }

    private fun elapsed(run: Run): Long =
        (SystemClock.elapsedRealtime() - run.startedAt).coerceAtLeast(0)

    private fun stop(run: Run, reason: String) {
        if (active !== run || run.retiring) return
        if (run.stopReason == null) {
            run.stopReason = reason
            if (run.ready)
                run.channel?.invokeMethod(
                    "stop",
                    mapOf("invocation" to run.invocation, "reason" to reason),
                )
        }
        if (reason == "foreground" && run.foregroundTimer == null) {
            run.configuration.foregroundStopTimeoutMs?.let { grace ->
                run.foregroundTimer =
                    Runnable {
                        if (active === run) retire(run, "forcedTeardown", "foreground")
                    }
                        .also { main.postDelayed(it, grace) }
            }
        }
    }

    private fun retire(run: Run, outcome: String, reason: String? = null, error: String? = null) {
        if (active !== run || run.retiring) return
        run.retiring = true
        run.budgetTimer?.let(main::removeCallbacks)
        run.foregroundTimer?.let(main::removeCallbacks)
        val terminal = if (outcome == "completed" && run.stopReason != null) "stopped" else outcome
        var failure: Exception? = null
        try {
            run.channel?.setMethodCallHandler(null)
        } catch (exception: Exception) {
            failure = exception
        }
        try {
            run.engine?.destroy()
        } catch (exception: Exception) {
            run.teardownFailure = exception
            failure = exception
        }
        if (run.teardownFailure == null) {
            active = null
            retireUnselectedSchedule(run.configuration.identifier)
        }
        if (failure != null) {
            report(run.configuration.identifier, "failed", "teardown", failure.message)
            run.stopResults.forEach { it.error("teardown", failure.message, null) }
            run.stopResults.clear()
            run.completion(false)
            resumePending()
            return
        }
        if (terminal != "completed") report(run.configuration.identifier, terminal, reason, error)
        run.completion(terminal != "failed" && terminal != "forcedTeardown")
        run.stopResults.forEach { it.success(null) }
        run.stopResults.clear()
        resumePending()
    }

    private fun retireUnselectedSchedule(identifier: String) {
        val app = application ?: return
        scheduler.execute {
            try {
                val saved =
                    app.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                        .getString(CONFIGURATION, null)
                        ?.let(::JSONObject)
                val tasks = saved?.optJSONArray("tasks") ?: JSONArray()
                val selected =
                    saved?.optBoolean("enabled") == true &&
                        (0 until tasks.length()).any {
                            tasks.getJSONObject(it).getString("identifier") == identifier
                        }
                if (!selected)
                    WorkManager.getInstance(app).cancelUniqueWork(identifier).result.get()
            } catch (exception: Exception) {
                main.post { report(identifier, "failed", "schedule", exception.message) }
            }
        }
    }

    private fun report(
        identifier: String,
        outcome: String,
        reason: String? = null,
        error: String? = null,
    ) {
        val event =
            mapOf(
                "identifier" to identifier,
                "outcome" to outcome,
                "reason" to reason,
                "error" to error,
            )
        val fallback = {
            Log.w(TAG, "$identifier: $outcome (${reason ?: "task"})${error?.let { ": $it" } ?: ""}")
            Unit
        }
        observers.lastOrNull { it.observesOutcomes }?.report(event, fallback) ?: fallback()
    }
}
