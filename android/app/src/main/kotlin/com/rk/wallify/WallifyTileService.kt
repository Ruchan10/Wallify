package com.rk.wallify

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile that switches automatic wallpaper changes on and off.
 *
 * It writes the same `flutter.autoWallpaperEnabled` flag the in-app switch uses
 * and schedules or cancels the same WorkManager job, so the two stay in sync.
 */
class WallifyTileService : TileService() {

    override fun onStartListening() {
        updateTile()
    }

    override fun onClick() {
        val prefs = WidgetUtils.getPrefs(this)
        val enable = !prefs.getBoolean(KEY_ENABLED, false)

        // commit, not apply: scheduleAutoChange reads this flag straight back and
        // bails out when it is false, and the process may die once the shade closes.
        prefs.edit().putBoolean(KEY_ENABLED, enable).commit()

        if (enable) {
            WorkManagerExt.scheduleAutoChange(this)
        } else {
            WorkManagerExt.cancelAutoChange(this)
        }

        updateTile()

        // Home screen widgets show the on/off state too.
        StatsWidget.triggerUpdate(this)
        QuickToggleWidget.triggerUpdate(this)
        ScheduleWidget.triggerUpdate(this)
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val enabled = WidgetUtils.getPrefs(this).getBoolean(KEY_ENABLED, false)

        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Auto Wallpaper"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (enabled) "On" else "Off"
        }
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_wallpaper)
        tile.updateTile()
    }

    private companion object {
        const val KEY_ENABLED = "flutter.autoWallpaperEnabled"
    }
}
