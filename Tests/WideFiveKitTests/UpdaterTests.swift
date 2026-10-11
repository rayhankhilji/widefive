import XCTest
@testable import WideFiveKit

final class UpdaterTests: XCTestCase {
    let feed = "https://github.com/rayhankhilji/widefive/releases/latest/download/appcast.xml"
    let key = Data(repeating: 7, count: 32).base64EncodedString()

    func testDisabledWhenRunningFromSource() {
        XCTAssertEqual(Updater.configurationProblem(info: ["SUFeedURL": feed, "SUPublicEDKey": key], isPackagedApp: false), "running from source")
    }

    func testDisabledWithoutSigningKey() {
        XCTAssertNotNil(Updater.configurationProblem(info: ["SUFeedURL": feed], isPackagedApp: true))
        XCTAssertNotNil(Updater.configurationProblem(info: ["SUFeedURL": feed, "SUPublicEDKey": "__SPARKLE_PUBLIC_KEY__"], isPackagedApp: true))
    }

    func testDisabledWithoutHTTPSFeed() {
        XCTAssertNotNil(Updater.configurationProblem(info: ["SUPublicEDKey": key], isPackagedApp: true))
        XCTAssertNotNil(Updater.configurationProblem(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": key], isPackagedApp: true))
    }

    func testEnabledWhenFullyConfigured() {
        XCTAssertNil(Updater.configurationProblem(info: ["SUFeedURL": feed, "SUPublicEDKey": key], isPackagedApp: true))
    }

    func testSourceBuildVersion() {
        XCTAssertEqual(Updater.versionDescription, "dev (from source)")
    }
}
