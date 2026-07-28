package com.rk.wallify

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import java.io.File

class RecentStackService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return RecentStackFactory(applicationContext)
    }
}

class RecentStackFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private val items = mutableListOf<RecentItem>()

    data class RecentItem(val path: String, val time: String)

    override fun onCreate() { loadData() }

    override fun onDataSetChanged() { loadData() }

    private fun loadData() {
        items.clear()
        try {
            val prefs = WidgetUtils.getPrefs(context)
            val raw = prefs.getString("flutter.recentWallpaperInfo", "[]") ?: "[]"
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                items.add(RecentItem(
                    path = obj.optString("path", ""),
                    time = obj.optString("time", "")
                ))
            }
            items.reverse()
        } catch (_: Exception) { }
    }

    override fun getCount(): Int = items.size.coerceAtLeast(1)

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_stack_item)

        if (items.isEmpty()) {
            views.setTextViewText(R.id.tv_stack_item_time, "No wallpapers yet")
            return views
        }

        val item = items[position]
        views.setTextViewText(R.id.tv_stack_item_time, item.time)

        val file = File(item.path)
        if (file.exists()) {
            try {
                val bm = BitmapFactory.decodeFile(file.absolutePath)
                if (bm != null) {
                    val scaled = android.graphics.Bitmap.createScaledBitmap(bm, 360, 360, true)
                    views.setImageViewBitmap(R.id.iv_stack_item, scaled)
                    if (bm !== scaled) bm.recycle()
                }
            } catch (_: Exception) { }
        }

        val fillIntent = android.content.Intent().apply {
            putExtra("position", position)
        }
        views.setOnClickFillInIntent(R.id.iv_stack_item, fillIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
    override fun onDestroy() {}
}
