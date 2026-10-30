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
            com.commutescout.drive.design.DayGlassTheme(scheme) {
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
            // Day Glass+ scenes for screenshots: "csForceAlert" = a kind
            // (crash, closure, hazard, police, jam, chain, fire, ice, sign,
            // camera, toll) put on the route ahead once a trip runs;
            // csClearing clears it again before it is reached; cs3D starts
            // in 3D; csSeeMore opens the alert; csGallery = catalog or
            // system draws every alert or every app message.
            if (intent?.getBooleanExtra("cs3D", false) == true) Engine.prefs.is3D = true
            if (intent?.getBooleanExtra("csSeeMore", false) == true) model.wantedOpen = true
            val clearing = intent?.getBooleanExtra("csClearing", false) == true
            if (clearing) DebugScenes.clearedHoldMs = 30_000L
            (intent?.getStringExtra("csForceAlert") ?: if (clearing) "crash" else null)?.let { k ->
                DebugScenes.forceAhead(k, clearAfterMs = if (clearing) 7000L else null)
            }
            intent?.getStringExtra("csGallery")?.let { model.wantedGallery = it }
            // "csPage" = watches, watchedit, offline, picker or savedmap opens
            // that page; csFixtures fills it with made-up data, signed out.
            if (intent?.getBooleanExtra("csFixtures", false) == true) MorePages.fixtures = true
            intent?.getStringExtra("csPage")?.let { MorePages.wanted = it }
            // "csArrive" shows the arrive sheet for a made-up trip, for screenshots.
            if (intent?.getBooleanExtra("csArrive", false) == true) model.showArriveDemo()
            ReportDebug.preview = intent?.getBooleanExtra("csReportPreview", false) == true
            // "csView" = "lat,lon,zoom" puts the camera somewhere, for screenshots.
            intent?.getStringExtra("csView")?.split(",")?.mapNotNull { it.toDoubleOrNull() }?.takeIf { it.size == 3 }?.let { model.wantedView = it }
            // "csTour" zooms and pans through a set of views, for a recording.
            if (intent?.getBooleanExtra("csTour", false) == true) model.wantedTour = true
            // "csOpenAlert" = "kind,lat,lon" acts out a tapped watch alert;
            // csAlertId, csAlertTitle, csAlertBody and csAlertWatch fill in
            // the rest of the push. The kind takes either naming. csAlertStatus
            // "cleared" acts out the follow-up push that says it is over.
            intent?.getStringExtra("csOpenAlert")?.split(",")?.takeIf { it.size >= 3 }?.let { p ->
                AlertTap.parse(mapOf(
                    "event_kind" to p[0], "event_lat" to p[1], "event_lon" to p[2],
                    "event_id" to intent.getStringExtra("csAlertId"),
                    "event_title" to (intent.getStringExtra("csAlertTitle") ?: "Test alert"),
                    "event_body" to (intent.getStringExtra("csAlertBody") ?: "A test alert from a debug build."),
                    "event_watch" to (intent.getStringExtra("csAlertWatch") ?: "Home area"),
                    "event_sent_at" to (System.currentTimeMillis() / 1000 - 25 * 60).toString(),
                    "event_status" to intent.getStringExtra("csAlertStatus"),
                    "event_lane_layout" to intent.getStringExtra("csAlertLanes"),
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
        val data = keys.associateWith { extras.getString(it) }
        if (AlertTap.opensWatchAreas(data)) { model.requestTool(Tool.WATCHES); return }
        AlertTap.parse(data)?.let { model.openAlert(it) }
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
