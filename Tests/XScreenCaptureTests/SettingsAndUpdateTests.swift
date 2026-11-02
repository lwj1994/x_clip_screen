import AppKit
import AppleViewModel
import XCTest
@testable import XScreenCapture

final class SettingsAndUpdateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { ViewModel.reset() }
    }

    override func tearDown() {
        MainActor.assumeIsolated { ViewModel.reset() }
        super.tearDown()
    }

    func testVersionComparisonIgnoresPrefixAndMissingComponents() {
        XCTAssertGreaterThan(AppVersion("v0.2.10"), AppVersion("0.2.9"))
        XCTAssertEqual(AppVersion("0.2"), AppVersion("v0.2.0"))
        XCTAssertLessThan(AppVersion("0.2.3"), AppVersion("0.2.4-beta"))
        XCTAssertEqual(AppVersion("v0.2.4").description, "0.2.4")
    }

    func testReleaseParsingPrefersAppArchive() throws {
        let json = """
        {"tag_name": "v0.2.4", "html_url": "https://github.com/lwj1994/x_clip_screen/releases/tag/v0.2.4",
         "assets": [
           {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
           {"name": "XScreenCapture-0.2.4.app.zip", "browser_download_url": "https://example.com/a.app.zip"}
         ]}
        """
        let release = try GitHubReleaseClient.parse(Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("0.2.4"))
        XCTAssertEqual(release.archiveURL, URL(string: "https://example.com/a.app.zip"))

        let withoutArchive = try GitHubReleaseClient.parse(Data(#"{"tag_name":"v1","html_url":"https://x.test","assets":[]}"#.utf8))
        XCTAssertNil(withoutArchive.archiveURL)
        XCTAssertThrowsError(try GitHubReleaseClient.parse(Data(#"{"tag_name":"latest"}"#.utf8)))
    }

    @MainActor
    func testSettingsPersistAndPostStatus() {
        let suite = "milu.qqjietu.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let spec = ViewModelSpec<SettingsViewModel>(key: "settings-test") { SettingsViewModel(defaults: defaults) }
        let binding = ViewModelBinding()
        defer { binding.dispose() }
        var settings: SettingsViewModel { binding.read(spec) }

        XCTAssertEqual(settings.state, SettingsState(highResolution: true, playSound: false,
                                                     borderColorHex: "#0099FF", automaticUpdateCheck: true))
        settings.setBorderColor(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
        XCTAssertEqual(settings.state.borderColorHex, "#FF8000")
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.borderColor), "#FF8000")
        XCTAssertEqual(binding.read(statusSpec).state.message, "选框颜色已保存，下次截图生效。")
        settings.setAutomaticUpdateCheck(false)
        XCTAssertFalse(defaults.bool(forKey: DefaultsKey.automaticUpdateCheck))
        settings.resetBorderColor()
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.borderColor), SelectionColor.defaultHex)
        XCTAssertEqual(SelectionColor.hex(from: SelectionColor.color(fromHex: "#12ABEF")), "#12ABEF")
    }
}
