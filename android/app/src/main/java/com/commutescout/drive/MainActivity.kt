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
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import com.stadiamaps.ferrostar.core.AndroidTtsStatusListener
import java.util.Locale

class MainActivity : ComponentActivity(), AndroidTtsStatusListener {
    private val model: DriveViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Engine.tts.statusObserver = this
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced = false
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            model.setLocationPermission(true)
        }
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = Color(0xFF1F5FCF))) {
                Surface { DriveScreen(model) }
            }
        }
        if (intent?.getBooleanExtra("csAutoDrive", false) == true && BuildConfig.DEBUG) {
            AutoDrive.run(model)
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
