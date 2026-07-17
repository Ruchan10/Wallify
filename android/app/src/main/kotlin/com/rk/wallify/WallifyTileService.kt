package com.rk.wallify

import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class WallifyTileService : TileService() {

    override fun onStartListening() {
        updateTile()
    }

    override fun onClick() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val current = prefs.getBoolean("flutter.autoWallpaperEnabled", false)
        prefs.edit().putBoolean("flutter.autoWallpaperEnabled", !current).apply()

        if (current) {
            WorkManagerExt.cancelAutoChange(this)
        } else {
            WorkManagerExt.scheduleAutoChange(this)
        }

        updateTile()

        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.autoWallpaperEnabled", false)

        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (enabled) "Auto Wallpaper ON" else "Auto Wallpaper OFF"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (enabled) "Tap to disable" else "Tap to enable"
        }

        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_wallpaper)
        tile.updateTile()
    }
}
