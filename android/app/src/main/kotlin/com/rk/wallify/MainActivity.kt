    package com.rk.wallify

    import io.flutter.embedding.android.FlutterActivity
    import io.flutter.embedding.engine.FlutterEngine
    import io.flutter.embedding.engine.FlutterEngineCache
    import android.app.NotificationChannel
    import android.app.NotificationManager
    import android.os.Build
    import android.util.Log
    import android.content.Intent
    import io.flutter.plugin.common.MethodChannel
    import android.content.IntentFilter
    import com.rk.wallify.PowerReceiver
    import android.os.Bundle

    class MainActivity : FlutterActivity() {
        private val START_SERVICE_CHANNEL = "wallify/start_service"
        private val chargeDetector = PowerReceiver()

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            registerReceiver(chargeDetector, IntentFilter(Intent.ACTION_POWER_CONNECTED))
        }
        
        companion object {
            var serviceEngine: FlutterEngine? = null
        }

        override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
            super.configureFlutterEngine(flutterEngine)
            serviceEngine = flutterEngine
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    "wallify_channel",
                    "Wallify Background Service",
                    NotificationManager.IMPORTANCE_LOW
                )
                val manager = getSystemService(NotificationManager::class.java)
                manager.createNotificationChannel(channel)
            }
        }


    }
