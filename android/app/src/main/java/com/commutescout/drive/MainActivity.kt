package com.commutescout.drive

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import com.stadiamaps.ferrostar.core.AndroidTtsStatusListener
import java.util.Locale

class MainActivity : ComponentActivity(), AndroidTtsStatusListener {
    internal val model: DriveViewModel by viewModels()   // internal: instrumented tests drive it

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Engine.tts.statusObserver = this
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced = false
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            model.setLocationPermission(true)
        }
        setContent {
            val dark = when (model.prefs.theme) {
                Prefs.Theme.SYSTEM -> isSystemInDarkTheme()
                Prefs.Theme.LIGHT -> false
                Prefs.Theme.DARK -> true
            }
            val scheme = if (dark) darkColorScheme(primary = Color(0xFF8AB4F8), surface = Color(0xFF16181C), background = Color(0xFF16181C))
                         else lightColorScheme(primary = Color(0xFF1F5FCF))
            SideEffect { model.isDark = dark }
            MaterialTheme(colorScheme = scheme) {
                Surface { DriveScreen(model) }
            }
        }
        // Test hooks, debug builds only: the same flags as the iOS app.
        if (BuildConfig.DEBUG) {
            if (intent?.getBooleanExtra("csResetPlaces", false) == true) Engine.places.removeAll()
            if (intent?.getBooleanExtra("csResetPrefs", false) == true) Engine.prefs.resetForTests()
            if (intent?.getBooleanExtra("csSimulate", false) == true) model.simulating.value = true
            if (intent?.getBooleanExtra("csAutoDrive", false) == true) AutoDrive.run(model)
        }
    }

    override fun onStart() {
        super.onStart()
        Engine.tts.start()
    }

    override fun onDestroy() {
        super.onDestroy()
        Engine.tts.shutdown()
    }

    override fun onTtsInitialized(tts: TextToSpeech?, status: Int) {
        tts?.language = Locale.getDefault()
    }

    override fun onTtsSpeakError(utteranceId: String, status: Int) {}

    override fun onTtsShutdownAndRelease() {}
}
