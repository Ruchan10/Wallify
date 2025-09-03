package com.rk.wallify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine

class PowerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_POWER_CONNECTED) {
            Log.d("PowerReceiver", "Device is plugged in!")

            // Get cached FlutterEngine
            val flutterEngine = FlutterEngineCache.getInstance().get("wallify_engine")
            if (flutterEngine != null) {
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wallify_channel")
                    .invokeMethod("changeWallpaper", null)
            } else {
                Log.d("PowerReceiver", "FlutterEngine not ready")
            }
        }
    }
}
