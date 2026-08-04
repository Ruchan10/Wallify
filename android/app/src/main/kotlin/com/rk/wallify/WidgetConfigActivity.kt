package com.rk.wallify

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.RadioGroup

class WidgetConfigActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.widget_config)

        val appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val currentLocation = prefs.all["flutter.wallpaperLocation"]?.let {
            when (it) {
                is Int -> it
                is Long -> it.toInt()
                is String -> it.toIntOrNull()
                else -> null
            }
        } ?: 3
        val currentSource = prefs.getString("flutter.wallpaperSource", "internet") ?: "internet"

        val locationGroup = findViewById<RadioGroup>(R.id.location_group)
        locationGroup.check(
            when (currentLocation) {
                1 -> R.id.radio_home
                2 -> R.id.radio_lock
                else -> R.id.radio_both
            }
        )

        val chkInternet = findViewById<CheckBox>(R.id.chk_internet)
        val chkFavorites = findViewById<CheckBox>(R.id.chk_favorites)
        val chkFolder = findViewById<CheckBox>(R.id.chk_folder)
        chkInternet.isChecked = currentSource.contains("internet")
        chkFavorites.isChecked = currentSource.contains("favorites")
        chkFolder.isChecked = currentSource.contains("folder")

        findViewById<Button>(R.id.btn_save).setOnClickListener {
            val location = when (locationGroup.checkedRadioButtonId) {
                R.id.radio_home -> 1
                R.id.radio_lock -> 2
                else -> 3
            }
            val sources = listOf(
                "internet" to chkInternet.isChecked,
                "favorites" to chkFavorites.isChecked,
                "folder" to chkFolder.isChecked,
            ).filter { it.second }.map { it.first }
            val sourceStr = if (sources.isEmpty()) "internet" else sources.joinToString(",")

            prefs.edit()
                .putInt("flutter.wallpaperLocation", location)
                .putString("flutter.wallpaperSource", sourceStr)
                .apply()

            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            )
            finish()
        }

        findViewById<Button>(R.id.btn_cancel).setOnClickListener {
            setResult(RESULT_CANCELED)
            finish()
        }
    }
}
