import XCTest
@testable import MarkdownViewer

/// Tests for AppearanceSettings mode cycling, icon names, and labels.
///
/// AppearanceSettings manages a 3-state appearance cycle (system -> light -> dark -> system).
/// Each mode maps to a specific SF Symbol icon and a human-readable label used in
/// the toolbar button and tooltip.
final class AppearanceSettingsTests: XCTestCase {

    private var savedMode: Int?

    override func setUp() {
        super.setUp()
        savedMode = UserDefaults.standard.object(forKey: "appearanceMode") as? Int
        // Reset to system mode for consistent test starting state
        let settings = AppearanceSettings.shared
        settings.mode = .system
    }

    override func tearDown() {
        if let savedMode {
            UserDefaults.standard.set(savedMode, forKey: "appearanceMode")
        } else {
            UserDefaults.standard.removeObject(forKey: "appearanceMode")
        }
        // Restore to system mode to avoid side effects on the running test process
        AppearanceSettings.shared.mode = .system
        super.tearDown()
    }

    // MARK: - cycle() state machine

    func testCycleFromSystemGoesToLight() {
        let settings = AppearanceSettings.shared
        settings.mode = .system

        settings.cycle()

        XCTAssertEqual(settings.mode, .light)
    }

    func testCycleFromLightGoesToDark() {
        let settings = AppearanceSettings.shared
        settings.mode = .light

        settings.cycle()

        XCTAssertEqual(settings.mode, .dark)
    }

    func testCycleFromDarkGoesToSystem() {
        let settings = AppearanceSettings.shared
        settings.mode = .dark

        settings.cycle()

        XCTAssertEqual(settings.mode, .system)
    }

    func testFullCycleReturnsToOriginalMode() {
        let settings = AppearanceSettings.shared
        settings.mode = .system

        settings.cycle() // -> light
        settings.cycle() // -> dark
        settings.cycle() // -> system

        XCTAssertEqual(settings.mode, .system)
    }

    // MARK: - iconName computed property

    func testIconNameForSystem() {
        let settings = AppearanceSettings.shared
        settings.mode = .system
        XCTAssertEqual(settings.iconName, "circle.lefthalf.filled")
    }

    func testIconNameForLight() {
        let settings = AppearanceSettings.shared
        settings.mode = .light
        XCTAssertEqual(settings.iconName, "sun.max.fill")
    }

    func testIconNameForDark() {
        let settings = AppearanceSettings.shared
        settings.mode = .dark
        XCTAssertEqual(settings.iconName, "moon.fill")
    }

    // MARK: - label computed property

    func testLabelForSystem() {
        let settings = AppearanceSettings.shared
        settings.mode = .system
        XCTAssertEqual(settings.label, "Appearance: System")
    }

    func testLabelForLight() {
        let settings = AppearanceSettings.shared
        settings.mode = .light
        XCTAssertEqual(settings.label, "Appearance: Light")
    }

    func testLabelForDark() {
        let settings = AppearanceSettings.shared
        settings.mode = .dark
        XCTAssertEqual(settings.label, "Appearance: Dark")
    }

    // MARK: - Each mode produces a distinct icon and label

    func testAllModesHaveDistinctIcons() {
        let settings = AppearanceSettings.shared
        settings.mode = .system
        let systemIcon = settings.iconName
        settings.mode = .light
        let lightIcon = settings.iconName
        settings.mode = .dark
        let darkIcon = settings.iconName

        XCTAssertNotEqual(systemIcon, lightIcon)
        XCTAssertNotEqual(lightIcon, darkIcon)
        XCTAssertNotEqual(systemIcon, darkIcon)
    }

    func testAllModesHaveDistinctLabels() {
        let settings = AppearanceSettings.shared
        settings.mode = .system
        let systemLabel = settings.label
        settings.mode = .light
        let lightLabel = settings.label
        settings.mode = .dark
        let darkLabel = settings.label

        XCTAssertNotEqual(systemLabel, lightLabel)
        XCTAssertNotEqual(lightLabel, darkLabel)
        XCTAssertNotEqual(systemLabel, darkLabel)
    }
}
