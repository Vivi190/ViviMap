import CoreLocation
import XCTest

/// Launches the app on the simulator at a fixed Istanbul position and keeps day/night screenshots as
/// test attachments; CI exports them so design changes can be reviewed without a device.
final class HomeScreenshotTests: XCTestCase {
    @MainActor
    func testHomeScreenDayAndNight() throws {
        continueAfterFailure = false
        // Kartal coast: the D-100 side roads, the coastal road and dense streets in one frame.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.8890, longitude: 29.1905))

        for appearance in ["day", "night"] {
            let app = XCUIApplication()
            app.launchArguments += ["-atlas.appearance", appearance]
            app.launch()
            allowLocationIfAsked()

            XCTAssertTrue(app.buttons["Konumumu göster"].waitForExistence(timeout: 20), "map controls did not appear")
            // MapLibre exposes no "tiles loaded" signal to XCUITest; give the network a fixed window.
            Thread.sleep(forTimeInterval: 10)

            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "home-\(appearance)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
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
