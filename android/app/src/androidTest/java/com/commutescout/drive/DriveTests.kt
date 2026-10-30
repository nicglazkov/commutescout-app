package com.commutescout.drive

import android.Manifest
import android.content.Intent
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToLog
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.geometry.Offset
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.By
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Every workflow a driver can do, on the emulator or a phone, with a
 * simulated location (the app is launched with csSimulate so routes start
 * from downtown San Jose). Mirrors ios/UITests. Anything that depends on
 * being signed in or on live data nearby is tolerated, not assumed.
 */
@RunWith(AndroidJUnit4::class)
class DriveTests {
    @get:Rule val compose = createEmptyComposeRule()
    /** A hang fails with a stack trace instead of stalling the suite. */
    @get:Rule val timeout: org.junit.rules.Timeout = org.junit.rules.Timeout.seconds(240)
    @get:Rule val location: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(vararg flags: String) {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(ctx, MainActivity::class.java)
        for (f in listOf("csSimulate", "csResetPlaces", "csResetPrefs") + flags) intent.putExtra(f, true)
        scenario = ActivityScenario.launch(intent)
        // Process singletons outlive activities: a trip left by an earlier test is stopped here.
        scenario?.onActivity { if (it.model.state.value !is DriveState.Browsing) it.model.stopNavigation() }
        compose.waitUntil(45_000) { compose.onAllNodesWithTag("search").fetchSemanticsNodes().isNotEmpty() }
    }

    @Before fun start() {
        // A busy Compose gives up in seconds, not the default 26, so the fallback can take over.
        androidx.test.espresso.IdlingPolicies.setIdlingResourceTimeout(6, java.util.concurrent.TimeUnit.SECONDS)
        launch()
    }
    @After fun stop() { scenario?.close() }

    private fun tag(t: String): SemanticsNodeInteraction = compose.onNodeWithTag(t, useUnmergedTree = true)
    private fun text(t: String, sub: Boolean = false) = compose.onNodeWithText(t, substring = sub, useUnmergedTree = true)
    private fun waitFor(timeoutMs: Long = 15_000, what: () -> Boolean) = compose.waitUntil(timeoutMs) { what() }
    private fun exists(t: String) = compose.onAllNodesWithText(t, substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    private fun tagExists(t: String) = whileBusy({ device().hasObject(By.res(t)) }) {
        compose.onAllNodesWithTag(t, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }
    /** A tap that still lands while a live trip keeps Compose from going idle. */
    private fun click(t: String) = whileBusy({ device().findObject(By.res(t))?.click() ?: throw AssertionError("no node tagged $t") }) {
        tag(t).performClick(); Unit
    }
    private fun device() = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    /**
     * While navigating, the map camera follows the car frame by frame and
     * Compose may not report idle. Then the same check goes through
     * UiAutomator, which reads the screen without waiting.
     */
    private fun <T> whileBusy(fallback: () -> T, block: () -> T): T = try { block() } catch (e: Throwable) {
        val busy = generateSequence(e) { it.cause }.any { c -> c::class.java.simpleName.let { "NotIdle" in it || "IdlingResourceTimeout" in it } }
        if (!busy) throw e
        fallback()
    }
    private fun existsExact(t: String) = compose.onAllNodesWithText(t, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun search(q: String) {
        tag("search").performClick()
        tag("search").performTextInput(q)
    }

    private fun pickSuggestion(prefix: String) {
        waitFor(20_000) { exists("$prefix,") }
        compose.onAllNodesWithText("$prefix,", substring = true, useUnmergedTree = true)[0].performClick()
    }

    /** Sheets scroll: bring a row into view before touching it. */
    private fun scrollTo(node: SemanticsNodeInteraction): SemanticsNodeInteraction {
        runCatching { node.performScrollTo() }
        return node
    }

    private fun openSettings() { tag("settings").performClick(); waitFor { tagExists("settings-sheet") } }
    /** Settings is a home page of categories; this opens one, by its name. */
    private fun openSettingsPage(name: String) {
        if (!tagExists("settings-sheet")) openSettings()
        if (tagExists("settings-back")) settingsHome()
        scrollTo(tag("settings-" + name.lowercase().replace(' ', '-'))).performClick()
        waitFor { tagExists("settings-back") }
    }
    /** Back until the home page: a page can sit on another (Alerts, then each kind). */
    private fun settingsHome() {
        for (i in 0 until 4) {
            if (!tagExists("settings-back")) return
            compose.onAllNodesWithTag("settings-back", useUnmergedTree = true)[0].performClick()
            compose.waitForIdle()
        }
        waitFor { !tagExists("settings-back") }
    }
    private fun openTool(t: String) { tag("tools").performClick(); waitFor { tagExists("tools-sheet") }; tag(t).performClick() }
    /** A tap on the scrim above the sheet closes it, as a person would.
     *  Injected by the system so Compose's idle wait cannot stall on the map. */
    private fun closeSheet(sheetTag: String) {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        // Back first (closes a keyboard, then the sheet), then the scrim, then a drag down.
        for (i in 0 until 3) {
            if (!tagExists(sheetTag)) return
            device.pressBack(); Thread.sleep(600)
        }
        if (tagExists(sheetTag)) { device.click(device.displayWidth / 2, 60); Thread.sleep(600) }
        if (tagExists(sheetTag)) device.swipe(device.displayWidth / 2, (device.displayHeight * 0.15).toInt(), device.displayWidth / 2, device.displayHeight - 10, 15)
        waitFor(8_000) { !tagExists(sheetTag) }
    }
    private fun stopNavigation() { scenario?.onActivity { it.model.stopNavigation() } }

    // MARK: search and places

    @Test fun searchIsLiveWhileTypingThenPinRoutesNavigateAndStop() {
        search("Palo Alto")
        pickSuggestion("Palo Alto")
        waitFor { tagExists("navigate") }
        tag("navigate").performClick()
        waitFor(45_000) { tagExists("start") }
        if (tagExists("route-1")) { tag("route-1").performClick(); tag("route-0").performClick() }
        tag("start").performClick()
        waitFor(45_000) { !tagExists("search") }    // navigating: the search bar is gone
        click("perspective"); click("perspective")
        stopNavigation()
        waitFor { tagExists("search") }
    }

    @Test fun coordinatesBecomeAPin() {
        search("37.442, -122.143")
        tag("search").performImeAction()
        waitFor { tagExists("navigate") }
        tag("place-close").performClick()
        waitFor { !tagExists("navigate") }
    }

    @Test fun nonsenseSearchSaysNothingYet() {
        search("zzqqxxyy")
        waitFor { exists("Nothing yet") }
    }

    @Test fun saveHomeWorkFavoriteThenShortcutsAndRemoveInSettings() {
        search("Palo Alto")
        pickSuggestion("Palo Alto")
        waitFor { tagExists("save-menu") }
        tag("save-menu").performClick(); waitFor { exists("Save as Home") }; text("Save as Home").performClick()
        tag("save-menu").performClick(); waitFor { exists("Save as Work") }; text("Save as Work").performClick()
        tag("save-menu").performClick(); waitFor { exists("Save to favorites") }; text("Save to favorites").performClick()
        tag("place-close").performClick()
        tag("search").performClick()
        waitFor { exists("Home") && exists("Work") }
        text("Home").performClick()
        waitFor { tagExists("navigate") }
        tag("place-close").performClick()
        openSettingsPage("Saved places")
        scrollTo(text("Home")).assertIsDisplayed()
        val remove = compose.onAllNodesWithContentDescription("Remove", useUnmergedTree = true)
        val n = remove.fetchSemanticsNodes().size
        assertTrue("remove buttons on place rows: $n", n >= 3)
        remove[0].performClick()
        waitFor { compose.onAllNodesWithContentDescription("Remove", useUnmergedTree = true).fetchSemanticsNodes().size == n - 1 }
    }

    @Test fun quickPicksOrderAndRemove() {
        search("Palo Alto"); pickSuggestion("Palo Alto")
        waitFor { tagExists("save-menu") }
        tag("save-menu").performClick(); waitFor { exists("Save as Home") }; text("Save as Home").performClick()
        tag("save-menu").performClick(); waitFor { exists("Save to favorites") }; text("Save to favorites").performClick()
        tag("place-close").performClick()
        tag("search").performClick()
        waitFor { exists("Home") }
        val removes = compose.onAllNodesWithTag("remove-place", useUnmergedTree = true)
        val n = removes.fetchSemanticsNodes().size
        assertTrue("remove buttons on quick picks: $n", n >= 2)
        removes[0].performClick()   // Home is first
        waitFor { compose.onAllNodesWithTag("remove-place", useUnmergedTree = true).fetchSemanticsNodes().size == n - 1 }
        assertTrue(!exists("Home"))
    }

    @Test fun unitsChangeThePlaceCard() {
        openSettingsPage("Units")
        scrollTo(text("Kilometers")).performClick()
        closeSheet("settings-sheet")
        search("Palo Alto"); pickSuggestion("Palo Alto")
        waitFor { exists(" km") }
        tag("place-close").performClick()
        openSettingsPage("Units")
        scrollTo(text("Miles")).performClick()
    }

    // MARK: settings

    @Test fun settingsHomeListsEveryCategoryWithItsValue() {
        openSettings()
        for (name in listOf("account", "map-style", "units", "voice", "alerts", "navigation", "map-layers", "plugins",
                            "offline-maps", "saved-places", "help", "about")) scrollTo(tag("settings-$name")).assertIsDisplayed()
        // A row says what it is set to without being opened.
        assertTrue(exists("Miles,") || exists("Kilometers,"))
        assertTrue(exists("Fastest") || exists("Avoids"))
        closeSheet("settings-sheet")
    }

    @Test fun settingsSwitchesPickersAndPerspective() {
        fun flip(vararg labels: String) { for (label in labels) { val sw = scrollTo(tag("switch-$label")); sw.performClick(); sw.performClick() } }
        openSettingsPage("Map style")
        for (s in listOf("dark", "outdoors", "positron")) scrollTo(tag("basemap-$s")).performClick()
        openSettingsPage("Units")
        for (u in listOf("km", "miles", "auto")) scrollTo(tag("unit-distance-$u")).performClick()
        openSettingsPage("Navigation")
        flip("Avoid tolls", "Avoid highways", "Avoid ferries", "Show speed limit", "Keep the screen on")
        openSettingsPage("Alerts")
        flip("Speak plugin alerts")
        scrollTo(tag("alerts-per-kind")).performClick()
        waitFor { tagExists("advanced-alerts") }
        scrollTo(tag("switch-Set alerts per kind")).performClick()
        waitFor { exists("Incidents") }
        scrollTo(text("Reset to defaults")).performClick()
        scrollTo(tag("switch-Set alerts per kind")).performClick()
        // Back steps out one page at a time, to the home page, not out of Settings.
        settingsHome()
        assertTrue(tagExists("settings-sheet"))
        closeSheet("settings-sheet")
    }

    @Test fun layerSwitchesForEveryKind() {
        openSettingsPage("Map layers")
        val traffic = scrollTo(tag("switch-Traffic")); traffic.performClick(); traffic.performClick()
        for (k in Prefs.layerKinds) { val sw = scrollTo(tag("switch-${k.label}")); sw.performClick(); sw.performClick() }
        openSettingsPage("About")
        scrollTo(text("Version", sub = true)).assertIsDisplayed()
        scrollTo(text("Privacy")).assertIsDisplayed()
        openSettingsPage("Help")
        for (label in listOf("Live map on the web", "Data sources", "Developers and API")) scrollTo(text(label, sub = true)).assertIsDisplayed()
    }

    @Test fun accountRowSignedOutOrIn() {
        openSettingsPage("Account")
        if (exists("Signed in as")) {
            scrollTo(text("Delete account")).performClick()
            waitFor { exists("Delete your account?") }
            text("Cancel").performClick()
            waitFor { !exists("Delete your account?") }
            text("Sign out").assertIsDisplayed()
        } else {
            scrollTo(text("Sign in with Google", sub = true)).assertIsDisplayed()
        }
    }

    // MARK: tools

    @Test fun toolsOpenEachPage() {
        openTool("tool-alerts"); waitFor { tagExists("alerts-sheet") }; closeSheet("alerts-sheet")
        openTool("tool-ask"); waitFor { tagExists("ask-sheet") }; closeSheet("ask-sheet")
        openTool("tool-sources"); waitFor { tagExists("sources-sheet") }
        waitFor { exists("Approved plugins") || exists("Public plugins") }
        scrollTo(tag("add-source")).performClick()
        waitFor { tagExists("source-url") }
        tag("source-url").performTextInput("http://example.com")
        // The keyboard sits over the buttons; put it away as a person would.
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        scrollTo(tag("source-add")).performClick()
        waitFor { exists("must start with https://") }
        closeSheet("sources-sheet")
        openTool("tool-watches"); waitFor { tagExists("watches-sheet") }
        assertTrue(exists("Sign in") || exists("watch"))
        closeSheet("watches-sheet")
        openTool("tool-layers"); waitFor { tagExists("layers-sheet") }
        for (st in listOf("dark", "positron")) scrollTo(tag("basemap-$st")).performClick()
        closeSheet("layers-sheet")
    }

    @Test fun marketplaceTilesAndInstall() {
        openTool("tool-marketplace"); waitFor { tagExists("marketplace-sheet") }
        waitFor(20_000) { tagExists("plugin-card") || exists("No plugin is listed yet") }
        if (tagExists("plugin-card")) {
            val btns = compose.onAllNodes(androidx.compose.ui.test.hasTestTag("install-wz-flare"), useUnmergedTree = true)
            if (btns.fetchSemanticsNodes().isNotEmpty()) {
                val wasAdded = existsExact("Added")
                btns[0].performClick()
                waitFor { existsExact(if (wasAdded) "Add" else "Added") }
                compose.onAllNodes(androidx.compose.ui.test.hasTestTag("install-wz-flare"), useUnmergedTree = true)[0].performClick()
            }
        }
        closeSheet("marketplace-sheet")
    }

    @Test fun alertsNearbyRowShowsTheMarkerCard() {
        openTool("tool-alerts"); waitFor { tagExists("alerts-sheet") }
        Thread.sleep(3000)
        val rows = compose.onAllNodesWithText(" mi", substring = true, useUnmergedTree = true)
        if (rows.fetchSemanticsNodes().isNotEmpty()) {
            rows[0].performClick()
            waitFor { !tagExists("alerts-sheet") }
            waitFor { tagExists("marker-card") }
        } else {
            assertTrue(exists("Nothing reported"))
        }
    }

    @Test fun directionsFromAnotherPlaceShowsRoutes() {
        openTool("tool-directions"); waitFor { tagExists("directions-sheet") }
        tag("from-field").performClick(); tag("from-field").performTextInput("Palo Alto")
        waitFor(20_000) { exists("Palo Alto,") }
        compose.onAllNodesWithText("Palo Alto,", substring = true, useUnmergedTree = true)[0].performClick()
        tag("to-field").performClick(); tag("to-field").performTextInput("Palo Alto")
        waitFor(20_000) { exists("Palo Alto,") }
        compose.onAllNodesWithText("Palo Alto,", substring = true, useUnmergedTree = true)[0].performClick()
        scrollTo(text("Show routes")).performClick()
        waitFor { !tagExists("directions-sheet") }
        waitFor(60_000) { tagExists("start") }
        tag("routes-close").performClick()
    }

    @Test fun askAnswersAQuestion() {
        openTool("tool-ask"); waitFor { tagExists("ask-field") }
        tag("ask-field").performTextInput("Is there anything on US-101 near San Jose right now?")
        tag("ask-send").performClick()
        waitFor(60_000) { compose.onAllNodesWithText("", substring = true, useUnmergedTree = true).fetchSemanticsNodes().any { n ->
            (n.config.getOrNull(SemanticsProperties.Text)?.joinToString()?.length ?: 0) > 60 } }
    }

    // MARK: reports and map controls

    @Test fun reportSheetEveryKindNoteAndCancel() {
        waitFor { tagExists("report") }
        // The report spot is the fix or the map center; give the map a moment to report one.
        for (i in 0 until 5) {
            tag("report").performClick()
            if (runCatching { waitFor(3_000) { tagExists("report-sheet") } }.isSuccess) break
            Thread.sleep(1000)
        }
        waitFor { tagExists("report-sheet") }
        val kinds = compose.onAllNodesWithTag("report-POLICE_VISIBLE", useUnmergedTree = true)
        assertTrue(kinds.fetchSemanticsNodes().isNotEmpty())
        tag("report-POLICE_VISIBLE").performClick()
        scrollTo(tag("report-CRASH_MAJOR")).performClick()
        // Signed out: the sheet says so and Send leads to sign-in. Signed in: Send is enabled.
        assertTrue(exists("Reports need an account") || runCatching { scrollTo(tag("report-send")).assertIsEnabled() }.isSuccess)
        closeSheet("report-sheet")   // never send a test report
    }

    @Test fun mapButtonsWhileBrowsing() {
        waitFor { tagExists("perspective") }
        tag("perspective").performClick(); tag("perspective").performClick()
        tag("locate").performClick()
        tag("perspective").assertIsDisplayed()
    }

    @Test fun autoDriveShowsNavigationAndStripCollapses() {
        scenario?.close()
        launch("csAutoDrive")
        waitFor(60_000) { !tagExists("search") }
        waitFor { tagExists("perspective") }
        assertTrue("Ferrostar owns recenter while navigating", !tagExists("locate"))
        if (runCatching { waitFor(45_000) { tagExists("alert-strip") } }.isSuccess) {
            click("alert-collapse")
            waitFor { tagExists("alert-pill") }
            click("alert-pill")
            waitFor { tagExists("alert-strip") }
        }
        stopNavigation()
        Thread.sleep(3000)
        scenario?.onActivity { android.util.Log.i("CSTEST", "after stop: navigating=${it.model.navigationUiState.value.isNavigating()} state=${it.model.state.value::class.simpleName} coreTrip=${Engine.core.state.value.tripState?.let { t -> t::class.simpleName }} calc=${Engine.core.state.value.isCalculatingNewRoute} progress=${it.model.navigationUiState.value.progress != null}") }
        if (runCatching { waitFor(30_000) { tagExists("search") } }.isFailure) {
            compose.onRoot(useUnmergedTree = true).printToLog("CSTEST")
            throw AssertionError("search bar did not return after stopping navigation")
        }
    }

    @Test fun longPressDropsAPin() {
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val x = device.displayWidth / 2; val y = (device.displayHeight * 0.45).toInt()
        device.swipe(x, y, x, y, 120)   // a still press of about a second
        waitFor(20_000) { tagExists("navigate") }
        tag("place-close").performClick()
    }
}
