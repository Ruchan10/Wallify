package com.rk.wallify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class PowerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("PowerReceiver", "INITIALIZE")

        if (intent?.action == Intent.ACTION_POWER_CONNECTED) {
            Log.d("PowerReceiver", "Device plugged in — notifying service")

            // Get the FlutterEngine running background service
            val engine = FlutterEngineCache.getInstance().get("wallify_engine")

            if (engine != null) {
                val channel = MethodChannel(engine.dartExecutor, "id.flutter.background_service")
                channel.invokeMethod("sendData", mapOf(
                    "method" to "WALLIFY_CHARGING_EVENT",
                    "args" to emptyMap<String, Any>()
                ))
            } else {
                Log.e("PowerReceiver", "No FlutterEngine available!")
            }
        }
    }
}
