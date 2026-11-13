package io.ente.background

import android.app.Application
import android.content.Context
import android.os.Looper
import androidx.work.Configuration
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.Operation
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkInfo
import androidx.work.impl.WorkManagerImpl
import androidx.work.testing.WorkManagerTestInitHelper
import com.google.common.util.concurrent.Futures
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
@LooperMode(LooperMode.Mode.PAUSED)
class BackgroundSchedulingTest {
    private val app: Application
        get() = RuntimeEnvironment.getApplication()

    private fun policy(identifier: String) =
        TaskConfiguration(
            identifier,
            "refresh",
            900_000,
            86_400_000,
            null,
            false,
            false,
            false,
            null,
            null,
            1,
        )

    private fun configure(vararg tasks: TaskConfiguration): Reply {
        val result = Reply()
        BackgroundRuntime.configure(
            mapOf(
                "enabled" to true,
                "callbackHandle" to 1L,
                "tasks" to
                    tasks.map { task ->
                        val json = JSONObject(task.encode())
                        json.keys().asSequence().associateWith { key ->
                            json.get(key).takeUnless { it === JSONObject.NULL }
                        }
                    },
            ),
            result,
        )
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!result.done && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(5)
        }
        assertTrue("Configuration did not finish", result.done)
        return result
    }

    @Test
    fun removedSchedulesAreRecoveredFromWorkManager() {
        WorkManagerTestInitHelper.initializeTestWorkManager(app, Configuration.Builder().build())
        BackgroundRuntime.install(app) { true }
        val original = WorkManagerImpl.getInstance(app)
        val manager = spy(original)
        WorkManagerImpl.setDelegate(manager)
        try {
            val kept = policy("schedule.kept")
            val removed = policy("schedule.removed")
            assertNull(configure(kept, removed).error)
            val failure = mock(Operation::class.java)
            `when`(failure.result)
                .thenReturn(
                    Futures.immediateFailedFuture(IllegalStateException("Cancellation failed"))
                )
            doReturn(failure).`when`(manager).cancelUniqueWork(removed.identifier)
            assertEquals("schedule", configure(kept).error)
            assertFalse(
                manager
                    .getWorkInfosForUniqueWork(removed.identifier)
                    .get()
                    .single()
                    .state
                    .isFinished
            )
            doCallRealMethod().`when`(manager).cancelUniqueWork(removed.identifier)
            assertNull(configure(kept).error)
            assertEquals(
                WorkInfo.State.CANCELLED,
                manager.getWorkInfosForUniqueWork(removed.identifier).get().single().state,
            )

            val interrupted = policy("schedule.interrupted")
            assertNull(configure(kept, interrupted).error)
            val preferences =
                app.getSharedPreferences("ente_background_manager", Context.MODE_PRIVATE)
            val desired = JSONObject(preferences.getString("configuration", null)!!)
            desired.put("tasks", JSONArray(listOf(JSONObject(kept.encode()))))
            assertTrue(preferences.edit().putString("configuration", desired.toString()).commit())
            assertNull(configure(kept).error)
            assertEquals(
                WorkInfo.State.CANCELLED,
                manager.getWorkInfosForUniqueWork(interrupted.identifier).get().single().state,
            )

            val reselected = policy("schedule.reselected")
            assertNull(configure(kept, reselected).error)
            doReturn(failure).`when`(manager).cancelUniqueWork(reselected.identifier)
            assertEquals("schedule", configure(kept).error)
            doCallRealMethod().`when`(manager).cancelUniqueWork(reselected.identifier)
            clearInvocations(manager)
            assertNull(configure(kept, reselected).error)
            verify(manager, never()).cancelUniqueWork(reselected.identifier)
            assertFalse(
                manager
                    .getWorkInfosForUniqueWork(reselected.identifier)
                    .get()
                    .single()
                    .state
                    .isFinished
            )

            val untagged = policy("schedule.untagged")
            fun enqueue(task: TaskConfiguration) {
                val request =
                    PeriodicWorkRequest.Builder(BackgroundWorker::class.java, 15, TimeUnit.MINUTES)
                        .setInitialDelay(1, TimeUnit.DAYS)
                        .setInputData(Data.Builder().putString("task", task.encode()).build())
                        .build()
                manager
                    .enqueueUniquePeriodicWork(
                        task.identifier,
                        ExistingPeriodicWorkPolicy.UPDATE,
                        request,
                    )
                    .result
                    .get()
            }
            enqueue(untagged)
            val previous = JSONObject(preferences.getString("configuration", null)!!)
            previous.put(
                "tasks",
                JSONArray(listOf(kept, reselected, untagged).map { JSONObject(it.encode()) }),
            )
            assertTrue(preferences.edit().putString("configuration", previous.toString()).commit())
            val unrelated = policy("schedule.unrelated")
            enqueue(unrelated)
            assertNull(configure(kept).error)
            assertEquals(
                WorkInfo.State.CANCELLED,
                manager.getWorkInfosForUniqueWork(untagged.identifier).get().single().state,
            )
            assertFalse(
                manager
                    .getWorkInfosForUniqueWork(unrelated.identifier)
                    .get()
                    .single()
                    .state
                    .isFinished
            )
        } finally {
            WorkManagerImpl.setDelegate(original)
        }
    }

    private class Reply : MethodChannel.Result {
        var done = false
        var error: String? = null

        override fun success(result: Any?) {
            assertFalse(done)
            done = true
        }

        override fun error(code: String, message: String?, details: Any?) {
            assertFalse(done)
            error = code
            done = true
        }

        override fun notImplemented() = fail("Unexpected method")
    }
}
