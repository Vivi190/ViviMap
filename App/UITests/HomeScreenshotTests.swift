import CoreLocation
import XCTest

/// Launches the app on the simulator at a fixed Istanbul position and keeps screenshots as test attachments;
/// CI exports them so design changes can be reviewed without a device.
final class HomeScreenshotTests: XCTestCase {
    @MainActor
    func testHomeSearchAnd3DNight() throws {
        continueAfterFailure = false
        // Kartal coast: the D-100 side roads, the coastal road and dense streets in one frame.
        // One launch only: on relaunch the simulator fell back to its default location (Apple Park).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.8890, longitude: 29.1905))
        let app = XCUIApplication()
        app.launchArguments += ["-atlas.appearance", "day", "-atlas.simulation", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["Konumumu göster"].waitForExistence(timeout: 20), "map controls did not appear")
        // The app starts following the user on its first fix; the button then shows the filled symbol.
        let fixed = waitForFirstFix(app, timeout: 40)
        if !fixed { capture("0-no-fix") } // evidence: is an alert still up, where is the map?
        XCTAssertTrue(fixed, "no location fix")
        // MapLibre exposes no "tiles loaded" signal to XCUITest; give the network a fixed window.
        settle(10)
        capture("1-home-day")

        // A place badge of the map opens that place's card. Soft: where a badge sits depends on live map data
        // (this is the station beside the start position), so a miss costs a screenshot, not the run.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.593, dy: 0.546)).tap()
        if app.otherElements["place.card"].waitForExistence(timeout: 8) {
            settle(3) // the address follows the name
            capture("1a-badge-card")
            app.buttons["Kapat"].firstMatch.tap()
        }
        // Street zoom, reviewed from the screenshot: one-way arrows and the place classes drawn from zoom 16.5.
        // No assertion: what shows depends on live tiles.
        let street = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33))
        street.doubleTap()
        settle(2)
        street.doubleTap()
        settle(8)
        capture("1b-street")

        // Search (live Photon request) → pick the first result → place card + pin.
        app.buttons["search.open"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "search field missing")
        // The sheet focuses its field by itself, but not yet on a slow runner ("no keyboard focus" after a
        // 128 s cold launch); a tap on a focused field changes nothing.
        field.tap()
        field.typeText("Kartal Adliyesi")
        let result = app.buttons.matching(identifier: "search.result").firstMatch
        // Photon is a shared public server and fails at times: one retry, with the evidence kept.
        if !result.waitForExistence(timeout: 20) {
            capture("2-search-retry")
            field.typeText(" ") // the same text once trimmed: searches again
        }
        XCTAssertTrue(result.waitForExistence(timeout: 20), "no search result")
        // A fresh simulator shows the slide-to-type tip over the keyboard on first use; it covered the results.
        let tip = app.buttons["Continue"]
        if tip.exists { tip.tap() }
        capture("2-search-results")
        result.tap()
        XCTAssertTrue(app.otherElements["place.card"].waitForExistence(timeout: 5), "place card missing")
        settle(6)
        capture("3-place")
        // Saved as home, it gets the "Ev" shortcut under the search pill (screenshots 4 and 6) and in search (2a).
        app.buttons["Diğer seçenekler"].tap()
        let saveHome = app.buttons["Ev olarak kaydet"]
        XCTAssertTrue(saveHome.waitForExistence(timeout: 5), "place menu missing")
        saveHome.tap()

        // Route (live FOSSGIS Valhalla request) → route card + line.
        app.buttons["place.route"].tap()
        XCTAssertTrue(app.otherElements["route.card"].waitForExistence(timeout: 30), "route card missing")
        settle(6)
        capture("3b-route")
        // The list of turns. Soft: reviewed from the screenshot, a miss must not cost the run.
        let directions = app.buttons["route.directions"]
        if directions.exists {
            directions.tap()
            let done = app.buttons["Bitti"]
            if done.waitForExistence(timeout: 5) {
                settle(1)
                capture("3b2-directions")
                done.tap()
                settle(2)
            }
        }

        // Guidance: banner with the first Turkish instruction, then end it.
        app.buttons["route.start"].tap()
        // The banner combines its children for VoiceOver, so it surfaces as a static text, not "other".
        XCTAssertTrue(app.descendants(matching: .any)["nav.banner"].waitForExistence(timeout: 15), "navigation banner missing")
        settle(6)
        capture("3c-navigation")
        app.buttons["nav.end"].tap()
        XCTAssertTrue(app.buttons["search.open"].waitForExistence(timeout: 5), "home screen did not return")

        // Simulated drive: the simulator's position stays put, so only the simulated fixes can move guidance on.
        app.buttons["search.open"].tap()
        let again = app.buttons.matching(identifier: "search.result").firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 20), "previous place not offered again")
        capture("2a-search-start") // after a drive: recents (and shortcuts, "Yakında" when the build has them)
        again.tap()
        XCTAssertTrue(app.buttons["place.route"].waitForExistence(timeout: 5), "place card missing")
        app.buttons["place.route"].tap()
        let simulate = app.buttons["route.simulate"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 30), "simulate button missing")
        simulate.tap()
        let banner = app.descendants(matching: .any)["nav.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "simulated guidance did not start")
        XCTAssertTrue(app.descendants(matching: .any)["nav.simulation"].exists, "simulation badge missing")
        settle(3)
        let before = banner.label
        settle(20)
        capture("3d-simulation")
        XCTAssertNotEqual(banner.label, before, "guidance did not advance during the simulated drive")
        // Car-mount landscape: panels in a left column, map on the right.
        XCUIDevice.shared.orientation = .landscapeLeft
        settle(5)
        capture("3e-landscape")
        XCUIDevice.shared.orientation = .portrait
        settle(3)
        // Whole route in view: the map stops following and "Rotaya devam et" brings it back to the car.
        app.buttons["Rotanın tamamı"].tap()
        let recenter = app.buttons["nav.recenter"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "no way back to the car after the overview")
        settle(2)
        capture("3f-overview")
        recenter.tap()
        settle(2)
        app.buttons["nav.end"].tap()
        XCTAssertTrue(app.buttons["search.open"].waitForExistence(timeout: 5), "home screen did not return after simulation")

        app.buttons["Üç boyutlu görünüm"].tap()
        settle(6)
        capture("4-home-day-3d")

        // Switch to night at runtime: exercises the style reload and the 3D layer re-applied after it.
        app.buttons["Harita ayarları"].tap()
        XCTAssertTrue(app.navigationBars["Harita"].waitForExistence(timeout: 5), "map settings sheet did not open")
        capture("5-map-settings")
        app.buttons["Gece"].tap()
        app.buttons["Bitti"].tap()
        settle(6)
        capture("6-home-night-3d")

        // Screens reviewed from screenshots only: the rest of the settings sheet and the drive log (empty on
        // CI, simulated drives are not recorded). Soft checks: a missing step costs a screenshot, not the run.
        app.buttons["Harita ayarları"].tap()
        guard app.navigationBars["Harita"].waitForExistence(timeout: 5) else { return }
        app.swipeUp()
        settle(1)
        capture("7-map-settings-more")
        let trips = app.staticTexts["Sürüşlerim"]
        guard trips.waitForExistence(timeout: 3) else { return }
        trips.tap()
        if app.navigationBars["Sürüşlerim"].waitForExistence(timeout: 5) { capture("8-trips") }

        // A search's results as pins on the map (night). Soft as well: Photon is a shared public server.
        let tripsBar = app.navigationBars["Sürüşlerim"]
        if tripsBar.exists { tripsBar.buttons.element(boundBy: 0).tap() }
        let done = app.buttons["Bitti"]
        guard done.waitForExistence(timeout: 3) else { return }
        done.tap()
        app.buttons["search.open"].tap()
        let query = app.searchFields.firstMatch
        guard query.waitForExistence(timeout: 5) else { return }
        query.tap()
        query.typeText("eczane")
        let onMap = app.buttons["search.showOnMap"]
        guard onMap.waitForExistence(timeout: 20) else { return }
        onMap.tap()
        settle(6)
        capture("9-results-map")
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for the app's first fix, accepting the location permission alert whenever it shows up (on a
    /// cold CI simulator it comes at varying times after launch). One run failed here with "no location fix"
    /// while MapLibre's own puck had a position; the cause is unconfirmed, so a failure now leaves the
    /// 0-no-fix screenshot as evidence.
    @MainActor
    private func waitForFirstFix(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = ["Allow While Using App", "Uygulamayı Kullanırken İzin Ver"].map { springboard.buttons[$0] }
        let fix = app.buttons["location.fill"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fix.exists { return true }
            allow.first(where: \.exists)?.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        return fix.exists
    }
}
