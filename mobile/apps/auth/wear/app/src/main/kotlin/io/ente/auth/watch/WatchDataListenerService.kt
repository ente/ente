package io.ente.auth.watch

import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

class WatchDataListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val hasSnapshotUpdate = dataEvents.any { event ->
            event.dataItem.uri.path?.startsWith("/auth/v1/snapshot/") == true
        }
        if (hasSnapshotUpdate) {
            WatchCompanion.syncInBackground(applicationContext)
        }
    }
}
