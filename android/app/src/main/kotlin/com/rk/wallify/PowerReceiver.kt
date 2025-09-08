package com.rk.wallify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache

class PowerReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        val isCharging = when(intent?.action) {
            Intent.ACTION_POWER_CONNECTED -> true
            else -> return
        }

        Log.e("PowerReceiver", "Charging status: $isCharging")

        // Send event to Flutter
        val engine = FlutterEngineCache.getInstance().get("background_engine")
        engine?.dartExecutor?.let { executor ->
            MethodChannel(executor, "wallify_channel").invokeMethod("charging", isCharging)
        }
    }
}
