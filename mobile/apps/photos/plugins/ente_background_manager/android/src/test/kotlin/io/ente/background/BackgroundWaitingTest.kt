package io.ente.background

import android.app.Application
import android.os.Looper
import androidx.work.Configuration
import androidx.work.Data
import androidx.work.ListenableWorker
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.view.FlutterCallbackInformation
import java.nio.ByteBuffer
import java.time.Duration
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.*
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class BackgroundWaitingTest {
    private val app: Application
        get() = RuntimeEnvironment.getApplication()

    private val startups = ArrayDeque<Runnable>()
    private val engines = ArrayList<Pair<FlutterEngine, Messenger>>()
    private val main
        get() = shadowOf(Looper.getMainLooper())

    private fun policy(budget: Long? = null, grace: Long? = null) =
        TaskConfiguration(
            "test.refresh",
            "refresh",
            900_000,
            86_400_000,
            null,
            false,
            false,
            false,
            budget,
            grace,
            1,
        )

    private fun configure(vararg policies: TaskConfiguration, enabled: Boolean = true) {
        val result = Reply()
        BackgroundRuntime.configure(
            mapOf(
                "enabled" to enabled,
                "callbackHandle" to 1L,
                "tasks" to
                    policies.map { policy ->
                        val data = org.json.JSONObject(policy.encode())
                        data.keys().asSequence().associateWith { key ->
                            data.get(key).takeUnless { it === org.json.JSONObject.NULL }
                        }
                    },
            ),
            result,
        )
        awaitReply(result)
    }

    private fun awaitReply(result: Reply) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!result.done && System.nanoTime() < deadline) {
            main.idle()
            Thread.sleep(5)
        }
        assertTrue("Configuration did not finish", result.done)
        assertNull(result.error)
    }

    private fun worker(policy: TaskConfiguration): BackgroundWorker =
        TestListenableWorkerBuilder<BackgroundWorker>(app)
            .setInputData(Data.Builder().putString("task", policy.encode()).build())
            .build()

    private fun bootstrap(): Messenger {
        startups.removeFirst().run()
        return engines.last().second
    }

    private fun complete(messenger: Messenger, ready: Map<*, *>, outcome: String = "completed") {
        messenger.call("complete", mapOf("invocation" to ready["invocation"], "outcome" to outcome))
    }

    private var allowed = true
    private val refresh = policy(budget = 60_000)
    private val processing =
        policy(budget = 30_000).copy(identifier = "test.processing", kind = "processing")

    @Before
    fun initialize() {
        resetRuntime()
        WorkManagerTestInitHelper.initializeTestWorkManager(app, Configuration.Builder().build())
        BackgroundRuntime.install(app) { allowed }
        val loader = mock(FlutterLoader::class.java)
        doAnswer { invocation ->
                startups.add(invocation.getArgument(3))
                null
            }
            .`when`(loader)
            .ensureInitializationCompleteAsync(any(), isNull(), any(), any())
        `when`(loader.findAppBundlePath()).thenReturn("flutter_assets")
        FlutterInjector.setInstance(FlutterInjector.Builder().setFlutterLoader(loader).build())
        BackgroundRuntime.findCallback = { mock(FlutterCallbackInformation::class.java) }
        BackgroundRuntime.createEngine = {
            val engine = mock(FlutterEngine::class.java)
            val executor = mock(DartExecutor::class.java)
            val messenger = Messenger()
            `when`(engine.dartExecutor).thenReturn(executor)
            `when`(executor.binaryMessenger).thenReturn(messenger)
            engines.add(engine to messenger)
            engine
        }

        configure(refresh, processing)
    }

    @After
    fun resetRuntime() {
        ReflectionHelpers.getField<android.os.Handler>(BackgroundRuntime, "main")
            .removeCallbacksAndMessages(null)
        ReflectionHelpers.setField(BackgroundRuntime, "application", null)
        ReflectionHelpers.setField(BackgroundRuntime, "active", null)
        ReflectionHelpers.setField(BackgroundRuntime, "waiting", null)
        ReflectionHelpers.setField(BackgroundRuntime, "isForeground", false)
        FlutterInjector.reset()
    }

    @Test
    fun processingCanWaitLongerThanThirtySeconds() {
        val longRefresh = refresh.copy(runBudgetMs = 600_000)
        val longProcessing = processing.copy(runBudgetMs = 480_000)
        configure(longRefresh, longProcessing)
        worker(longRefresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(longProcessing).startWork()
        main.idleFor(Duration.ofMinutes(2))
        assertFalse(pending.isDone)
        assertTrue(channel.sent.isEmpty())
        assertTrue(startups.isEmpty())
        complete(channel, ready)
        val next = bootstrap()
        val nextReady = next.call("ready") as Map<*, *>
        assertEquals(120_000L, nextReady["elapsedMs"])
        complete(next, nextReady)
        assertTrue(pending.isDone)
    }

    @Test
    fun cancelledWaitTimerCannotFinishReplacement() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val original = worker(processing)
        val cancelled = original.startWork()
        main.idleFor(Duration.ofSeconds(5))
        original.onStopped()
        main.idle()
        assertTrue(cancelled.isDone)
        val replacement = worker(processing).startWork()
        main.idleFor(Duration.ofSeconds(26))
        assertFalse(replacement.isDone)
        assertTrue(startups.isEmpty())
        complete(channel, ready)
        val next = bootstrap()
        val nextReady = next.call("ready") as Map<*, *>
        assertEquals(26_000L, nextReady["elapsedMs"])
        complete(next, nextReady)
        assertTrue(replacement.isDone)
    }

    @Test
    fun exhaustedBudgetNeverBootstrapsWaitingProcessing() {
        val expiredProcessing = processing.copy(runBudgetMs = 0)
        configure(refresh, expiredProcessing)
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        assertEquals(ListenableWorker.Result.success(), worker(expiredProcessing).startWork().get())
        assertTrue(channel.sent.isEmpty())
        complete(channel, ready)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun processingWaitsForEngineRetirementAndKeepsElapsedTime() {
        val running = worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        assertFalse(pending.isDone)
        assertTrue(startups.isEmpty())
        assertTrue(channel.sent.isEmpty())
        assertEquals(ListenableWorker.Result.success(), worker(processing).startWork().get())
        assertEquals(ListenableWorker.Result.success(), worker(refresh).startWork().get())
        main.idleFor(Duration.ofSeconds(5))
        doAnswer {
                assertTrue(startups.isEmpty())
                assertFalse(pending.isDone)
                null
            }
            .`when`(engines.single().first)
            .destroy()
        complete(channel, ready)
        assertTrue(running.isDone)
        assertFalse(pending.isDone)
        val next = bootstrap()
        val nextReady = next.call("ready") as Map<*, *>
        assertEquals(processing.identifier, nextReady["identifier"])
        assertEquals(5_000L, nextReady["elapsedMs"])
        assertEquals(30_000L, nextReady["runBudgetMs"])
        assertNull(nextReady["stopReason"])
        main.idleFor(Duration.ofSeconds(24))
        assertTrue(next.sent.isEmpty())
        main.idleFor(Duration.ofSeconds(1))
        assertEquals("budget", (next.sent.single().arguments as Map<*, *>)["reason"])
        complete(next, nextReady)
        assertEquals(ListenableWorker.Result.success(), pending.get())
        complete(channel, ready)
        main.idleFor(Duration.ofMinutes(1))
        assertEquals(2, engines.size)
    }

    @Test
    fun queuedBudgetExpiryLeavesRefreshRunning() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        main.idleFor(Duration.ofSeconds(30))
        assertEquals(ListenableWorker.Result.success(), pending.get())
        assertTrue(channel.sent.isEmpty())
        verify(engines.single().first, never()).destroy()
        complete(channel, ready)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun stoppedQueuedWorkerCannotStartAfterRefresh() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pendingWorker = worker(processing)
        val pending = pendingWorker.startWork()
        pendingWorker.onStopped()
        main.idle()
        assertTrue(pending.isDone)
        assertTrue(channel.sent.isEmpty())
        complete(channel, ready)
        pendingWorker.onStopped()
        main.idleFor(Duration.ofMinutes(1))
        assertTrue(startups.isEmpty())
    }

    @Test
    fun foregroundRemovesWaitingBeforeRefreshRetires() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        BackgroundRuntime.foreground()
        assertTrue(pending.isDone)
        assertEquals("foreground", (channel.sent.single().arguments as Map<*, *>)["reason"])
        complete(channel, ready)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun explicitStopClearsWaitingAndWaitsForRefreshRetirement() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        val result = Reply()
        BackgroundRuntime.requestStop(result)
        assertTrue(pending.isDone)
        assertFalse(result.done)
        assertEquals(ListenableWorker.Result.success(), worker(processing).startWork().get())
        complete(channel, ready)
        assertTrue(result.done)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun disablingBackendRemovesWaiting() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        configure(refresh, processing, enabled = false)
        assertTrue(pending.isDone)
        complete(channel, ready)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun removingProcessingScheduleRemovesWaitingWithoutStoppingRefresh() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        configure(refresh)
        assertTrue(pending.isDone)
        assertTrue(channel.sent.isEmpty())
        complete(channel, ready)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun flagRevocationIsRecheckedAtHandoff() {
        worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        allowed = false
        complete(channel, ready)
        assertTrue(pending.isDone)
        assertTrue(startups.isEmpty())
    }

    @Test
    fun refreshFailureStillAllowsProcessingAfterCleanup() {
        val running = worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        complete(channel, ready, "failed")
        assertEquals(ListenableWorker.Result.failure(), running.get())
        verify(engines.single().first).destroy()
        val next = bootstrap()
        val nextReady = next.call("ready") as Map<*, *>
        complete(next, nextReady)
        assertEquals(ListenableWorker.Result.success(), pending.get())
    }

    @Test
    fun teardownFailureDoesNotLaunchWaitingProcessing() {
        val running = worker(refresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        val pending = worker(processing).startWork()
        doThrow(IllegalStateException("Engine destruction failed"))
            .`when`(engines.single().first)
            .destroy()
        complete(channel, ready)
        assertEquals(ListenableWorker.Result.failure(), running.get())
        assertEquals(ListenableWorker.Result.failure(), pending.get())
        assertTrue(startups.isEmpty())
        main.idleFor(Duration.ofMinutes(1))
        assertEquals(1, engines.size)
    }

    @Test
    fun refreshBudgetStopDoesNotPreventWaitingProcessingFromStarting() {
        val shortRefresh = refresh.copy(runBudgetMs = 100)
        configure(shortRefresh, processing)
        worker(shortRefresh).startWork()
        val channel = bootstrap()
        val ready = channel.call("ready") as Map<*, *>
        main.idleFor(Duration.ofMillis(100))
        val pending = worker(processing).startWork()
        assertFalse(pending.isDone)
        assertEquals("budget", (channel.sent.single().arguments as Map<*, *>)["reason"])
        complete(channel, ready)
        val next = bootstrap()
        val nextReady = next.call("ready") as Map<*, *>
        assertNull(nextReady["stopReason"])
        complete(next, nextReady)
        assertTrue(pending.isDone)
    }

    @Test
    fun processingCanWaitWhileRefreshIsBootstrapping() {
        val running = worker(refresh).startWork()
        val pending = worker(processing).startWork()
        assertEquals(1, startups.size)
        main.idleFor(Duration.ofSeconds(5))
        BackgroundRuntime.findCallback = { null }
        startups.removeFirst().run()
        assertEquals(ListenableWorker.Result.failure(), running.get())
        BackgroundRuntime.findCallback = { mock(FlutterCallbackInformation::class.java) }
        val next = bootstrap()
        val ready = next.call("ready") as Map<*, *>
        assertEquals(5_000L, ready["elapsedMs"])
        complete(next, ready)
        assertTrue(pending.isDone)
    }

    private class Reply : MethodChannel.Result {
        var done = false
        var error: String? = null
        var value: Any? = null

        override fun success(result: Any?) {
            assertFalse("Reply already completed", done)
            value = result
            done = true
        }

        override fun error(code: String, message: String?, details: Any?) {
            assertFalse("Reply already completed", done)
            error = "$code: $message"
            done = true
        }

        override fun notImplemented() {
            assertFalse("Reply already completed", done)
            error = "notImplemented"
            done = true
        }
    }

    private class Messenger : BinaryMessenger {
        private val codec = StandardMethodCodec.INSTANCE
        private var handler: BinaryMessenger.BinaryMessageHandler? = null
        var failHandlerRemoval = false
        val sent = ArrayList<MethodCall>()

        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {
            message?.flip()
            sent.add(codec.decodeMethodCall(requireNotNull(message)))
            callback?.reply(codec.encodeSuccessEnvelope(null).also { it.flip() })
        }

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {
            check(handler != null || !failHandlerRemoval) { "Handler removal failed" }
            this.handler = handler
        }

        fun call(method: String, arguments: Any? = null): Any? {
            var reply: Any? = null
            handler?.onMessage(
                codec.encodeMethodCall(MethodCall(method, arguments)).also { it.flip() }
            ) { encoded ->
                encoded?.flip()
                reply = codec.decodeEnvelope(requireNotNull(encoded))
            }
            return reply
        }
    }
}
