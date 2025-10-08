package com.rk.wallify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class WallifyService : Service() {

    private val powerReceiver = PowerReceiver()
    private lateinit var engine: FlutterEngine

    override fun onCreate() {
        super.onCreate()

        Log.e("WallifyService", "Service created")

        // Setup foreground notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "wallify_channel",
                "Wallify Background Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)

            val notification: Notification = NotificationCompat.Builder(this, "wallify_channel")
                .setContentTitle("Wallify Running")
                .setContentText("Listening for charging events")
                .setSmallIcon(R.drawable.ic_bg_service_small) // Use custom notification icon
                .build()
            startForeground(1, notification)
        }

        // Initialize FlutterEngine
        engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put("background_engine", engine)

        // Register power receiver
        val filter = IntentFilter()
        filter.addAction(Intent.ACTION_POWER_CONNECTED)
        filter.addAction(Intent.ACTION_POWER_DISCONNECTED)
        registerReceiver(powerReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(powerReceiver)
        Log.e("WallifyService", "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
