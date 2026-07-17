package com.rk.wallify

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.RectF
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.service.wallpaper.WallpaperService
import android.view.MotionEvent
import android.view.SurfaceHolder
import java.io.File

class WallifyLiveWallpaper : WallpaperService() {

    override fun onCreateEngine(): Engine = LiveWallpaperEngine()

    private inner class LiveWallpaperEngine : Engine(), SensorEventListener {

        private val handler = Handler(Looper.getMainLooper())
        private var bitmap: Bitmap? = null
        private var visible = true

        private var sensorManager: SensorManager? = null
        private var tiltX = 0f
        private var tiltY = 0f
        private val parallaxStrength = 0.04f

        private val renderRunnable = object : Runnable {
            override fun run() {
                drawFrame()
                if (visible) handler.postDelayed(this, 16)
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder?) {
            super.onCreate(surfaceHolder)
            sensorManager = applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            loadBitmap()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            if (visible) {
                loadBitmap()
                handler.post(renderRunnable)
                sensorManager?.registerListener(
                    this,
                    sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR),
                    SensorManager.SENSOR_DELAY_GAME
                )
            } else {
                handler.removeCallbacks(renderRunnable)
                sensorManager?.unregisterListener(this)
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder?, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            drawFrame()
        }

        override fun onTouchEvent(event: MotionEvent?) {
            if (event?.action == MotionEvent.ACTION_DOWN) {
                val intent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                }
            }
            super.onTouchEvent(event)
        }

        override fun onSensorChanged(event: SensorEvent?) {
            event ?: return
            if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR) {
                val rotationMatrix = FloatArray(9)
                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                val orientation = FloatArray(3)
                SensorManager.getOrientation(rotationMatrix, orientation)
                tiltX = orientation[1]
                tiltY = orientation[2]
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        private fun loadBitmap() {
            val file = File(applicationContext.filesDir, "live_wallpaper.jpg")
            if (file.exists()) {
                bitmap = BitmapFactory.decodeFile(file.absolutePath)
            }
            if (bitmap == null) {
                bitmap = BitmapFactory.decodeResource(resources, android.R.drawable.ic_menu_gallery)
            }
        }

        private fun drawFrame() {
            val holder = surfaceHolder
            val bmp = bitmap ?: return
            var canvas: Canvas? = null
            try {
                canvas = holder?.lockCanvas() ?: return

                val surfW = canvas.width.toFloat()
                val surfH = canvas.height.toFloat()
                val imgW = bmp.width.toFloat()
                val imgH = bmp.height.toFloat()

                val scale = maxOf(surfW / imgW, surfH / imgH) * 1.15f
                val shiftX = tiltX * surfW * parallaxStrength
                val shiftY = tiltY * surfH * parallaxStrength
                val panX = (surfW - imgW * scale) / 2f + shiftX
                val panY = (surfH - imgH * scale) / 2f + shiftY
                val dst = RectF(panX, panY, panX + imgW * scale, panY + imgH * scale)

                canvas.drawBitmap(bmp, null, dst, null)
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                canvas?.let { holder?.unlockCanvasAndPost(it) }
            }
        }

        override fun onDestroy() {
            handler.removeCallbacks(renderRunnable)
            sensorManager?.unregisterListener(this)
            super.onDestroy()
        }
    }
}
