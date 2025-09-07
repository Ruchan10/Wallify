package com.rk.wallify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class PowerReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        val chargingStatus = when (intent?.action) {
            Intent.ACTION_POWER_CONNECTED -> true
            Intent.ACTION_POWER_DISCONNECTED -> false
            else -> null
        }

        chargingStatus?.let {
            Log.e("PowerReceiver", "Charging status: $it")

            // Send to Flutter background service
            val engine = MainActivity.serviceEngine
            engine?.dartExecutor?.let { executor ->
                MethodChannel(executor, "wallify_channel").invokeMethod(
                    "charging",
                    it
                )
            }
        }
    }
}
