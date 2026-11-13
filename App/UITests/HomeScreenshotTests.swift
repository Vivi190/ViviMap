import CoreLocation
import XCTest

/// Launches the app on the simulator at a fixed Istanbul position and keeps screenshots as test attachments;
/// CI exports them so design changes can be reviewed without a device.
final class HomeScreenshotTests: XCTestCase {
    // Kartal coast: the D-100 side roads, the coastal road and dense streets in one frame.
    private let kartal = CLLocation(latitude: 40.8890, longitude: 29.1905)

    @MainActor
    func testHomeScreenDayAndNight() throws {
        continueAfterFailure = false

        for appearance in ["day", "night"] {
            // Set before every launch: on relaunch the simulator fell back to its default location.
            XCUIDevice.shared.location = XCUILocation(location: kartal)
            let app = XCUIApplication()
            app.launchArguments += ["-atlas.appearance", appearance]
            app.launch()
            allowLocationIfAsked()

            XCTAssertTrue(app.buttons["Konumumu göster"].waitForExistence(timeout: 20), "map controls did not appear")
            // MapLibre exposes no "tiles loaded" signal to XCUITest; give the network a fixed window.
            Thread.sleep(forTimeInterval: 10)
            capture("home-\(appearance)")

            if appearance == "day" {
                app.buttons["Üç boyutlu görünüm"].tap()
                Thread.sleep(forTimeInterval: 6)
                capture("home-day-3d")

                app.buttons["Harita ayarları"].tap()
                XCTAssertTrue(app.navigationBars["Harita"].waitForExistence(timeout: 5), "map settings sheet did not open")
                capture("map-settings")
            }
            app.terminate()
        }
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
