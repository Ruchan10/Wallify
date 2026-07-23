package com.rk.wallify

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object WorkerLogger {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val LOG_KEY = "worker_logs"
    private const val MAX_ENTRIES = 200
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())

    private fun getPrefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun log(context: Context, level: String, tag: String, message: String) {
        try {
            val prefs = getPrefs(context)
            val raw = prefs.getString(LOG_KEY, "[]") ?: "[]"
            val arr = JSONArray(raw)

            val entry = JSONObject().apply {
                put("ts", dateFormat.format(Date()))
                put("level", level)
                put("tag", tag)
                put("msg", message)
            }

            arr.put(entry)
            while (arr.length() > MAX_ENTRIES) {
                arr.remove(0)
            }

            prefs.edit().putString(LOG_KEY, arr.toString()).apply()
        } catch (_: Exception) {
        }
    }

    fun i(context: Context, tag: String, message: String) = log(context, "I", tag, message)
    fun w(context: Context, tag: String, message: String) = log(context, "W", tag, message)
    fun e(context: Context, tag: String, message: String) = log(context, "E", tag, message)

    fun getLogs(context: Context): List<Map<String, String>> {
        return try {
            val prefs = getPrefs(context)
            val raw = prefs.getString(LOG_KEY, "[]") ?: "[]"
            val arr = JSONArray(raw)
            val result = mutableListOf<Map<String, String>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                result.add(mapOf(
                    "ts" to obj.optString("ts", ""),
                    "level" to obj.optString("level", ""),
                    "tag" to obj.optString("tag", ""),
                    "msg" to obj.optString("msg", "")
                ))
            }
            result
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun clearLogs(context: Context) {
        try {
            getPrefs(context).edit().remove(LOG_KEY).apply()
        } catch (_: Exception) {
        }
    }
}
