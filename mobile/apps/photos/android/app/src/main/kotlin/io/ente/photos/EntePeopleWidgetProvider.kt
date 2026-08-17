package io.ente.photos

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
data class PeopleFileData(
        val title: String?,
        val subText: String?,
        val generatedId: Int?,
        val mainKey: String?
)

class EntePeopleWidgetProvider : HomeWidgetProvider() {
        override fun onUpdate(
                context: Context,
                appWidgetManager: AppWidgetManager,
                appWidgetIds: IntArray,
                widgetData: SharedPreferences
        ) {
                appWidgetIds.forEach { widgetId ->
                        val views =
                                RemoteViews(context.packageName, R.layout.people_widget_layout)
                                        .apply {
                                                val totalPeople =
                                                        widgetData.getInt("totalPeople", 0)
                                                var randomNumber = -1
                                                var imagePath: String? = null
                                                if (totalPeople > 0) {
                                                        randomNumber =
                                                                (0 until totalPeople!!).random()
                                                        imagePath =
                                                                widgetData.getString(
                                                                        "people_widget_" +
                                                                                randomNumber,
                                                                        null
                                                                )
                                                }
                                                var imageExists: Boolean = false
                                                if (imagePath != null) {
                                                        val imageFile = File(imagePath)
                                                        imageExists = imageFile.exists()
                                                }
                                                if (imageExists) {
                                                        val data =
                                                                widgetData.getString(
                                                                        "people_widget_${randomNumber}_data",
                                                                        null
                                                                )
                                                        val decoded: PeopleFileData? =
                                                                data?.let {
                                                                        Json.decodeFromString<
                                                                                PeopleFileData>(it)
                                                                }
                                                        val title = decoded?.title
                                                        val subText = decoded?.subText
                                                        val generatedId = decoded?.generatedId
                                                        val mainKey = decoded?.mainKey

                                                        val deepLinkUri =
                                                                Uri.parse(
                                                                        "peoplewidget://message?generatedId=${generatedId}&mainKey=${mainKey}&homeWidget"
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
                                                                "EntePeopleWidgetProvider",
                                                                "Image exists: $imagePath"
                                                        )
                                                        val hideFlags =
                                                                widgetData.getInt(
                                                                        "widgetHideTitleFlags",
                                                                        0
                                                                )
                                                        val hideText =
                                                                (hideFlags and (1 shl 2)) != 0
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

                                                        val bitmap: Bitmap =
                                                                BitmapFactory.decodeFile(imagePath)
                                                        setImageViewBitmap(R.id.widget_img, bitmap)
                                                        setTextViewText(R.id.widget_title, title)
                                                        setTextViewText(
                                                                R.id.widget_subtitle,
                                                                subText
                                                        )
                                                } else {
                                                        val deepLinkUri =
                                                                Uri.parse(
                                                                        "peoplewidget://configure?homeWidget"
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
                                                                "EntePeopleWidgetProvider",
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
                                                                        R.drawable.ic_people_widget
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
