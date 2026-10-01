package com.visiosoil.app

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

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
}
