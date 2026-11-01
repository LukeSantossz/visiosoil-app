package com.visiosoil.app

import android.app.UiModeManager
import android.content.res.Configuration
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Bundle
import android.view.ViewTreeObserver
import android.view.WindowInsetsController
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter's first frame draws the splash tile exactly where the system
        // splash shows it, so the splash leaves at once. The platform's exit
        // animation would fade the icon, then the background, and slide the
        // window, dimming the tile at the hand-over (SPEC 0089).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view -> view.remove() }
        }
        // Android 12 to 14 draw the system splash over the whole display but
        // inset the app above the navigation bar, so the tile jumped at the
        // hand-over. Lay the window out as Android 15 does: edge to edge, with
        // transparent bars and the platform's scrim behind a three-button bar
        // only. Android 11 and earlier inset both windows, and 15+ enforces
        // this already, so both are left alone (SPEC 0109, #304).
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.S..Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            window.setDecorFitsSystemWindows(false)
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = true
            matchNavigationIconsToNightMode(resources.configuration)
            window.decorView.viewTreeObserver.addOnPreDrawListener(navigationBarKeeper)
        }
    }

    /**
     * Puts the see-through navigation bar back before each frame on Android 12
     * to 14. MaterialApp pushes `SystemUiOverlayStyle.dark` or `.light` on every
     * theme build, and both paint the bar opaque black with light icons, which
     * the app's own overlay style leaves alone. Checked before the frame draws,
     * so the black is never shown (SPEC 0109).
     */
    @get:RequiresApi(Build.VERSION_CODES.S)
    private val navigationBarKeeper = ViewTreeObserver.OnPreDrawListener {
        if (window.navigationBarColor != Color.TRANSPARENT) {
            window.navigationBarColor = Color.TRANSPARENT
        }
        matchNavigationIconsToNightMode(resources.configuration)
        true
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The night mode follows the user's theme choice (SPEC 0107), and the
        // manifest routes uiMode here rather than recreating the activity.
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.S..Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            matchNavigationIconsToNightMode(newConfig)
        }
    }

    /**
     * The see-through navigation bar's icons read on the app's background:
     * dark in the light theme, light in the dark one. Dart cannot set them,
     * because before Android 12 the bar is opaque black (SPEC 0109).
     */
    @RequiresApi(Build.VERSION_CODES.S)
    private fun matchNavigationIconsToNightMode(config: Configuration) {
        val night = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val wanted = if (night) 0 else WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
        val controller = window.insetsController ?: return
        // Skipped when already right, since the pre-draw keeper calls this
        // before every frame.
        if (controller.systemBarsAppearance and
            WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS == wanted
        ) {
            return
        }
        controller.setSystemBarsAppearance(
            wanted,
            WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The theme the user chose in Settings becomes the app's night mode,
        // which the system persists and reads when it draws the splash at the
        // next cold launch (SPEC 0107, #245). Before Android 12 there is no
        // per-app night mode, and the launch follows the system.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "visiosoil/appearance")
            .setMethodCallHandler { call, result ->
                if (call.method != "setNightMode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val mode = when (call.arguments as? String) {
                        "light" -> UiModeManager.MODE_NIGHT_NO
                        "dark" -> UiModeManager.MODE_NIGHT_YES
                        // "system", and anything unknown, clears the override.
                        else -> UiModeManager.MODE_NIGHT_AUTO
                    }
                    getSystemService(UiModeManager::class.java)
                        ?.setApplicationNightMode(mode)
                }
                result.success(null)
            }
        // The guided camera's distance estimate reads the open lens's optics,
        // and its light chip the ambient light sensor (SPEC 0238).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.visiosoil.app/camera_optics")
            .setMethodCallHandler { call, result ->
                if (call.method != "opticsOf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(opticsOf(call.arguments as String))
                } catch (e: Exception) {
                    result.error("optics_unavailable", e.message, null)
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.visiosoil.app/ambient_light")
            .setStreamHandler(AmbientLightHandler())
    }

    /**
     * The focal length and the active array's long side, in millimetres, of
     * the Camera2 camera [cameraId]; null when the camera reports either
     * incompletely. The active array is the part of the sensor the frames
     * come from, so its share of the physical size is what a frame spans.
     */
    private fun opticsOf(cameraId: String): Map<String, Double>? {
        val manager = getSystemService(CameraManager::class.java) ?: return null
        val characteristics = manager.getCameraCharacteristics(cameraId)
        val focal = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            ?.firstOrNull() ?: return null
        val physical = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            ?: return null
        val pixels = characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
            ?: return null
        val active = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            ?: return null
        val pixelLong = maxOf(pixels.width, pixels.height)
        if (focal <= 0f || pixelLong <= 0) return null
        val activeLong = maxOf(active.width(), active.height())
        val physicalLong = maxOf(physical.width, physical.height)
        return mapOf(
            "focalLengthMm" to focal.toDouble(),
            "activeLongSideMm" to physicalLong.toDouble() * activeLong / pixelLong,
        )
    }

    /** Streams the ambient light sensor's lux while Dart listens. */
    private inner class AmbientLightHandler : EventChannel.StreamHandler, SensorEventListener {
        private var events: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
            val manager = getSystemService(SensorManager::class.java)
            val sensor = manager?.getDefaultSensor(Sensor.TYPE_LIGHT)
            if (sensor == null) {
                // No sensor: the light chip keeps its verdict alone.
                sink.endOfStream()
                return
            }
            events = sink
            manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
        }

        override fun onCancel(arguments: Any?) {
            getSystemService(SensorManager::class.java)?.unregisterListener(this)
            events = null
        }

        override fun onSensorChanged(event: SensorEvent) {
            events?.success(event.values[0].toDouble())
        }

        override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
    }
}
