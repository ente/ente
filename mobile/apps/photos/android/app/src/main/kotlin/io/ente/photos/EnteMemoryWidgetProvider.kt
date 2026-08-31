package io.ente.photos

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

@Serializable
data class MemoryFileData(val title: String?, val subText: String?, val generatedId: Int?)

class EnteMemoryWidgetProvider : HomeWidgetProvider() {
        override fun onUpdate(
                context: Context,
                appWidgetManager: AppWidgetManager,
                appWidgetIds: IntArray,
                widgetData: SharedPreferences
        ) {
                appWidgetIds.forEach { widgetId ->
                        val views =
                                RemoteViews(context.packageName, R.layout.memory_widget_layout)
                                        .apply {
                                                val totalMemories =
                                                        widgetData.getInt("totalMemories", 0)
                                                var randomNumber = -1
                                                var imagePath: String? = null
                                                if (totalMemories > 0) {
                                                        randomNumber =
                                                                (0 until totalMemories!!).random()
                                                        imagePath =
                                                                widgetData.getString(
                                                                        "memory_widget_" +
                                                                                randomNumber,
                                                                        null
                                                                )
                                                }
                                                val existingImagePath =
                                                        imagePath?.takeIf { File(it).exists() }
                                                if (existingImagePath != null) {
                                                        val data =
                                                                widgetData.getString(
                                                                        "memory_widget_${randomNumber}_data",
                                                                        null
                                                                )
                                                        val decoded: MemoryFileData? =
                                                                data?.let {
                                                                        Json.decodeFromString<
                                                                                MemoryFileData>(it)
                                                                }
                                                        val title = decoded?.title
                                                        val subText = decoded?.subText
                                                        val generatedId = decoded?.generatedId

                                                        val deepLinkUri =
                                                                Uri.parse(
                                                                        "memorywidget://message?generatedId=${generatedId}&homeWidget"
                                                                )

                                                        val pendingIntent =
                                                                HomeWidgetLaunchIntent.getActivity(
                                                                        context,
                                                                        MainActivity::class.java,
                                                                        deepLinkUri
                                                                )

                                                        setOnClickPendingIntent(
                                                                R.id.widget_container,
                                                                pendingIntent
                                                        )

                                                        Log.d(
                                                                "EnteMemoryWidgetProvider",
                                                                "Image exists: $existingImagePath"
                                                        )
                                                        val hideFlags =
                                                                widgetData.getInt(
                                                                        "widgetHideTitleFlags",
                                                                        0
                                                                )
                                                        val hideText =
                                                                (hideFlags and (1 shl 0)) != 0
                                                        val textVisibility =
                                                                if (hideText) View.GONE
                                                                else View.VISIBLE
                                                        setViewVisibility(
                                                                R.id.widget_img,
                                                                View.VISIBLE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_subtitle,
                                                                textVisibility
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_title,
                                                                textVisibility
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_overlay,
                                                                textVisibility
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_title,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_text,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_container,
                                                                View.GONE
                                                        )

                                                        val bitmap =
                                                                decodeWidgetBitmap(existingImagePath)
                                                        setImageViewBitmap(R.id.widget_img, bitmap)
                                                        setTextViewText(R.id.widget_title, title)
                                                        setTextViewText(
                                                                R.id.widget_subtitle,
                                                                subText
                                                        )
                                                } else {
                                                        val deepLinkUri =
                                                                Uri.parse(
                                                                        "memorywidget://configure?homeWidget"
                                                                )
                                                        val pendingIntent =
                                                                HomeWidgetLaunchIntent.getActivity(
                                                                        context,
                                                                        MainActivity::class.java,
                                                                        deepLinkUri
                                                                )
                                                        setOnClickPendingIntent(
                                                                R.id.widget_container,
                                                                pendingIntent
                                                        )

                                                        Log.d(
                                                                "EnteMemoryWidgetProvider",
                                                                "Image doesn't exists"
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_img,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_subtitle,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_title,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_overlay,
                                                                View.GONE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder,
                                                                View.VISIBLE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_title,
                                                                View.VISIBLE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_text,
                                                                View.VISIBLE
                                                        )
                                                        setViewVisibility(
                                                                R.id.widget_placeholder_container,
                                                                View.VISIBLE
                                                        )

                                                        val drawable =
                                                                ContextCompat.getDrawable(
                                                                        context,
                                                                        R.drawable
                                                                                .ic_memories_widget
                                                                )
                                                        val bitmap =
                                                                (drawable as BitmapDrawable).bitmap
                                                        setImageViewBitmap(
                                                                R.id.widget_placeholder,
                                                                bitmap
                                                        )
                                                }
                                        }

                        appWidgetManager.updateAppWidget(widgetId, views)
                }
        }
}
