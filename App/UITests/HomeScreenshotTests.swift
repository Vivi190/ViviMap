import CoreLocation
import XCTest

/// Launches the app on the simulator at a fixed Istanbul position and keeps screenshots as test attachments;
/// CI exports them so design changes can be reviewed without a device.
final class HomeScreenshotTests: XCTestCase {
    @MainActor
    func testHomeScreenDayNightAnd3D() throws {
        continueAfterFailure = false
        // Kartal coast: the D-100 side roads, the coastal road and dense streets in one frame.
        // One launch only: on relaunch the simulator fell back to its default location (Apple Park).
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.8890, longitude: 29.1905))
        let app = XCUIApplication()
        app.launchArguments += ["-atlas.appearance", "day"]
        app.launch()
        allowLocationIfAsked()

        XCTAssertTrue(app.buttons["Konumumu göster"].waitForExistence(timeout: 20), "map controls did not appear")
        // MapLibre exposes no "tiles loaded" signal to XCUITest; give the network a fixed window.
        settle(10)
        capture("1-home-day")

        app.buttons["Üç boyutlu görünüm"].tap()
        settle(6)
        capture("2-home-day-3d")

        // Switch to night at runtime: exercises the style reload and the 3D layer re-applied after it.
        app.buttons["Harita ayarları"].tap()
        XCTAssertTrue(app.navigationBars["Harita"].waitForExistence(timeout: 5), "map settings sheet did not open")
        capture("3-map-settings")
        app.buttons["Gece"].tap()
        app.navigationBars["Harita"].swipeDown(velocity: .fast)
        settle(6)
        capture("4-home-night-3d")

        app.buttons["Üç boyutlu görünüm"].tap()
        settle(5)
        capture("5-home-night")
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

    @MainActor
    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Allow While Using App", "Uygulamayı Kullanırken İzin Ver"] {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 4) {
                button.tap()
                return
            }
        }
    }
}
