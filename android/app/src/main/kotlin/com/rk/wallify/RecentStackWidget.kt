package com.rk.wallify

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class RecentStackWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            val intent = Intent(context, RecentStackService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            val views = RemoteViews(context.packageName, R.layout.widget_recent_stack)
            views.setRemoteAdapter(R.id.stack_view, intent)
            views.setEmptyView(R.id.stack_view, R.id.tv_stack_overlay)
            views.setOnClickPendingIntent(R.id.widget_root, WidgetUtils.buildOpenAppIntent(context, appWidgetId))
            val openItemIntent = Intent(context, RecentStackWidget::class.java).apply {
                action = ACTION_VIEW_ITEM
            }
            val pIntent = android.app.PendingIntent.getBroadcast(
                context, appWidgetId, openItemIntent,
                WidgetUtils.getFlags()
            )
            views.setPendingIntentTemplate(R.id.stack_view, pIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_VIEW_ITEM) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = android.content.ComponentName(context, RecentStackWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    launchIntent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    context.startActivity(launchIntent)
                }
            }
        }
    }

    companion object {
        const val ACTION_VIEW_ITEM = "com.rk.wallify.stack.ACTION_VIEW_ITEM"

        fun triggerUpdate(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val component = android.content.ComponentName(context, RecentStackWidget::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                appWidgetManager.notifyAppWidgetViewDataChanged(ids, R.id.stack_view)
            }
        }
    }
}
