package com.commutescout.drive

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    internal val model: DriveViewModel by viewModels()   // internal: instrumented tests drive it

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
            // A stray back gesture from a mount must not end the trip's
            // screen; the app steps aside and the trip keeps going.
            val state by model.state.collectAsStateWithLifecycle()
            BackHandler(enabled = state is DriveState.Navigating) { moveTaskToBack(true) }
            MaterialTheme(colorScheme = scheme) {
                Surface { DriveScreen(model) }
            }
        }
        // A rotation brings the same intent back: the alert was opened already.
        if (savedInstanceState == null) intent?.let { openAlert(it) }
        // Test hooks, debug builds only: the same flags as the iOS app.
        if (BuildConfig.DEBUG) {
            if (intent?.getBooleanExtra("csResetPlaces", false) == true) Engine.places.removeAll()
            if (intent?.getBooleanExtra("csResetPrefs", false) == true) Engine.prefs.resetForTests()
            if (intent?.getBooleanExtra("csSimulate", false) == true) model.simulating.value = true
            if (intent?.getBooleanExtra("csAutoDrive", false) == true) AutoDrive.run(model)
            // "csView" = "lat,lon,zoom" puts the camera somewhere, for screenshots.
            intent?.getStringExtra("csView")?.split(",")?.mapNotNull { it.toDoubleOrNull() }?.takeIf { it.size == 3 }?.let { model.wantedView = it }
            // "csTour" zooms and pans through a set of views, for a recording.
            if (intent?.getBooleanExtra("csTour", false) == true) model.wantedTour = true
            // "csOpenAlert" = "kind,lat,lon" acts out a tapped watch alert;
            // csAlertId, csAlertTitle, csAlertBody and csAlertWatch fill in
            // the rest of the push. The kind takes either naming.
            intent?.getStringExtra("csOpenAlert")?.split(",")?.takeIf { it.size >= 3 }?.let { p ->
                AlertTap.parse(mapOf(
                    "event_kind" to p[0], "event_lat" to p[1], "event_lon" to p[2],
                    "event_id" to intent.getStringExtra("csAlertId"),
                    "event_title" to (intent.getStringExtra("csAlertTitle") ?: "Test alert"),
                    "event_body" to (intent.getStringExtra("csAlertBody") ?: "A test alert from a debug build."),
                    "event_watch" to (intent.getStringExtra("csAlertWatch") ?: "Home area"),
                    "event_sent_at" to (System.currentTimeMillis() / 1000 - 25 * 60).toString(),
                ))?.let { model.openAlert(it) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openAlert(intent)
    }

    /**
     * A tapped watch alert. The system draws the notification while the
     * app is in the background and puts the push's data keys on this
     * intent itself (event_id, url, ...); in the foreground PushService
     * draws it and copies the same keys, plus csUrl.
     */
    private fun openAlert(intent: Intent) {
        val extras = intent.extras ?: return
        val keys = listOf("url", "csUrl") + PushService.EVENT_KEYS
        AlertTap.parse(keys.associateWith { extras.getString(it) })?.let { model.openAlert(it) }
    }

    override fun onStart() {
        super.onStart()
        Engine.tts.start()
    }

    override fun onDestroy() {
        super.onDestroy()
        // A trip outlives the activity in the foreground service, and a
        // rotation brings the activity straight back: the guidance voice
        // must survive both. onStart starts it only when it is not running.
        if (!isChangingConfigurations && !Engine.tripActive) Engine.tts.shutdown()
    }
}
