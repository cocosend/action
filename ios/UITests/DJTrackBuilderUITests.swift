import XCTest

/// Tests the real app entry point and its navigable controls on an iOS simulator.
/// These checks intentionally avoid assuming sound hardware, signed builds,
/// Apple Music access, or source audio that was never imported.
final class DJTrackBuilderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--mixauto-ui-seeded")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20),
                      "The app failed to reach the foreground")
    }

    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground { app.terminate() }
    }

    func testLaunchDecksAndTransportAreVisible() throws {
        XCTAssertTrue(app.buttons["Play Deck A"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Play Deck B"].exists)
        XCTAssertTrue(app.sliders["Crossfader: A to B"].exists)
        XCTAssertTrue(app.buttons["Load audio to Deck A"].exists)
        XCTAssertTrue(app.buttons["Load audio to Deck B"].exists)
        XCTAssertTrue(app.buttons["Deck A SYNC"].exists)
        XCTAssertFalse(app.buttons["Deck A SYNC"].isEnabled,
                       "Imported song tempo SYNC must not appear working")
        XCTAssertTrue(app.buttons["Deck B SYNC"].exists)
        snapshot("01-wave-initial")
    }

    func testAllFiveModesAndAutoScreenNavigate() throws {
        let modes = ["MIX", "STEMS", "BUILDER", "FX", "WAVE"]
        for mode in modes {
            let button = app.buttons[mode]
            XCTAssertTrue(button.exists, "Missing navigation mode: \(mode)")
            button.tap()
            XCTAssertTrue(app.buttons["Play Deck A"].exists)
            XCTAssertTrue(app.buttons["Play Deck B"].exists)
            snapshot("02-\(mode.lowercased())")
        }
        let auto = app.buttons["Open Pattern AutoMix"]
        XCTAssertTrue(auto.exists)
        auto.tap()
        XCTAssertTrue(app.staticTexts["MIXAUTO / PHRASE PLAN"].waitForExistence(timeout: 5))
        snapshot("03-auto")
    }

    func testWaveformAndHotCueControls() throws {
        XCTAssertTrue(app.otherElements["Deck A waveform"].exists ||
                      app.staticTexts["PCM SIGNAL OVERVIEW · ORIGINAL PATTERNS"].exists)
        let cue = app.buttons["Deck A hot cue 1: set"]
        XCTAssertTrue(cue.exists, "Fixture must expose an empty file Hot Cue slot")
        cue.tap()
        XCTAssertTrue(app.buttons["Deck A hot cue 1: jump"].exists,
                      "Tapping empty Hot Cue must persist an actual cue")
        app.buttons["Deck Hot Cues Menu"].tap()
        let page = app.buttons["HOT CUES 5–8"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.tap()
        XCTAssertTrue(app.buttons["Deck A hot cue 5: set"].exists)
        snapshot("04-hot-cues")
    }

    func testImportedFileDeckTransportIsIndependent() throws {
        XCTAssertTrue(app.buttons["Play Deck A"].exists)
        XCTAssertTrue(app.buttons["Play Deck B"].exists)
        app.buttons["Play Deck A"].tap()
        XCTAssertTrue(app.buttons["Pause Deck A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play Deck B"].exists,
                      "Starting Deck A must not start Deck B")
        app.buttons["Pause Deck A"].tap()
        XCTAssertTrue(app.buttons["Play Deck A"].exists)
        snapshot("05-imported-dual-deck-transport")
    }

    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
