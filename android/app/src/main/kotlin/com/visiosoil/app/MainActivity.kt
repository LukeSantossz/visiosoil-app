package com.visiosoil.app

import android.app.UiModeManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
                        .setApplicationNightMode(mode)
                }
                result.success(null)
            }
    }
}
