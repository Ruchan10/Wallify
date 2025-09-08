    package com.rk.wallify

    import io.flutter.embedding.android.FlutterActivity
    import android.util.Log
    import android.content.Intent
    import android.os.Bundle

    class MainActivity : FlutterActivity() {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            val intent = Intent(this, WallifyService::class.java)
            startForegroundService(intent)
        }
    }
