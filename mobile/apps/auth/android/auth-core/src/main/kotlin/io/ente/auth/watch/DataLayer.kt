package io.ente.auth.watch

import android.content.Context
import android.net.Uri
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import java.util.concurrent.TimeUnit

internal class DataLayer(private val context: Context) {
    data class Item(val node: String, val path: String, val data: ByteArray)
    private var client: DataClient? = null
    private var localNode: String? = null
    private val sent = mutableMapOf<String, ByteArray>()
    private val deleted = mutableSetOf<String>()
    private var listener: DataClient.OnDataChangedListener? = null

    fun start(changed: () -> Unit) {
        if (client != null) return
        requireWatch(GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) ==
            ConnectionResult.SUCCESS, "watchUnavailable")
        val candidate = Wearable.getDataClient(context)
        GoogleApiAvailability.getInstance().checkApiAvailability(candidate).waitFor()
        localNode = Wearable.getNodeClient(context).localNode.waitFor().id
        val observer = DataClient.OnDataChangedListener { changed() }
        candidate.addListener(observer).waitFor()
        client = candidate
        listener = observer
    }

    fun stop() {
        val active = client
        listener?.let { active?.removeListener(it) }
        listener = null
        client = null
        sent.clear()
        deleted.clear()
    }

    fun items(): List<Item> {
        val buffer = (client ?: throw WatchException("watchUnavailable")).dataItems.waitFor()
        return try {
            buffer.mapNotNull { item ->
                val node = item.uri.host
                val path = item.uri.path
                val data = item.data
                if (node == null || node == localNode || path == null || data == null ||
                    !path.startsWith(ROOT)) null else Item(node, path, data.copyOf())
            }
        } finally { buffer.release() }
    }

    fun connectedNodes(): Set<String> = Wearable.getNodeClient(context).connectedNodes.waitFor()
        .map { it.id }.toSet()

    fun put(path: String, data: ByteArray) {
        if (sent[path]?.contentEquals(data) == true) return
        (client ?: throw WatchException("watchUnavailable"))
            .putDataItem(PutDataRequest.create(path).setData(data).setUrgent()).waitFor()
        sent[path] = data.copyOf()
        deleted.remove(path)
    }

    fun delete(path: String) {
        if (path in deleted) return
        val uri = Uri.Builder().scheme("wear").authority(localNode).path(path).build()
        (client ?: throw WatchException("watchUnavailable")).deleteDataItems(uri).waitFor()
        sent.remove(path)
        deleted.add(path)
    }

    companion object {
        const val ROOT = "/auth/v1/"
        const val CAPABILITIES = ROOT + "phone"
        const val STATUS = ROOT + "watch"
        fun snapshot(id: String) = ROOT + "snapshot/" + id
    }
}

private fun <T> Task<T>.waitFor(): T = Tasks.await(this, 10, TimeUnit.SECONDS)
