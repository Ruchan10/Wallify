package com.example.wallify

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cache engine for PowerReceiver
        FlutterEngineCache.getInstance().put("wallify_engine", flutterEngine)
    }
}
