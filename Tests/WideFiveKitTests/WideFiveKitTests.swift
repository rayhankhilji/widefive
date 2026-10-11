import XCTest
@testable import WideFiveKit

final class ConfigTests: XCTestCase {
    func testDefaultConfigRoundTrips() throws {
        let config = Config.default
        let decoded = try Config.decode(try config.encoded())
        XCTAssertEqual(config, decoded)
    }

    func testPartialConfigFillsDefaults() throws {
        let decoded = try Config.decode(Data(#"{"theme":"retro"}"#.utf8))
        XCTAssertEqual(decoded.theme, "retro")
        XCTAssertEqual(decoded.startMode, "home")
        XCTAssertTrue(decoded.gestures.enabled)
    }

    func testEveryDefaultAppLayoutMatchesItsBundleIds() {
        let config = Config.default
        XCTAssertFalse(config.apps.isEmpty)
        for app in config.apps {
            for id in app.bundleIds {
                XCTAssertNotNil(config.layout(for: id), "no layout for \(id)")
            }
        }
        XCTAssertNil(config.layout(for: "com.example.nothing"))
        XCTAssertNil(config.layout(for: nil))
    }
}

final class KeyTests: XCTestCase {
    func testParsesModifierChord() throws {
        let combo = try XCTUnwrap(Keys.parse("cmd+shift+p"))
        XCTAssertEqual(combo.keyCode, Keys.codes["p"])
        XCTAssertTrue(combo.flags.contains(.maskCommand))
        XCTAssertTrue(combo.flags.contains(.maskShift))
        XCTAssertFalse(combo.flags.contains(.maskControl))
    }

    func testParsesSpecialKeys() {
        XCTAssertNotNil(Keys.parse("ctrl+opt+left"))
        XCTAssertNotNil(Keys.parse("f5"))
        XCTAssertNotNil(Keys.parse("cmd+return"))
    }

    func testRejectsUnknownKey() {
        XCTAssertNil(Keys.parse("cmd+notakey"))
    }
}

final class EngineTests: XCTestCase {
    func makeFlatWorld(_ cols: Int = 40) -> TileWorld {
        let w = TileWorld()
        for _ in 0..<cols { var c = w.emptyColumn(); c[0] = .ground; w.append(c) }
        return w
    }

    func testBodyLandsOnGround() {
        let world = makeFlatWorld()
        var body = Body(x: 20, y: 20, w: 5, h: 6)
        for _ in 0..<120 { body.vy -= 600 / 60; world.move(&body, dt: 1 / 60) }
        XCTAssertEqual(body.y, TileWorld.T, accuracy: 0.01)
        XCTAssertTrue(body.onGround)
    }

    func testWallStopsBody() {
        let world = makeFlatWorld()
        world.set(10, 1, .block); world.set(10, 2, .block)
        var body = Body(x: 30, y: TileWorld.T, w: 5, h: 6)
        for _ in 0..<120 { body.vx = 60; body.vy -= 10; world.move(&body, dt: 1 / 60) }
        XCTAssertLessThanOrEqual(body.x + body.w, 10 * TileWorld.T + 0.01)
        XCTAssertTrue(body.hitWall)
    }

    func testSeededRNGIsDeterministic() {
        var a = SeededRNG(seed: 42), b = SeededRNG(seed: 42)
        XCTAssertEqual((0..<20).map { _ in a.next(1000) }, (0..<20).map { _ in b.next(1000) })
    }
}

final class MigrationTests: XCTestCase {
    func testV1ConfigGainsControlButtonAndLosesFlick() throws {
        let v1 = try Config.decode(Data(#"{"leading":[{"type":"button","icon":"square.grid.2x2.fill","action":{"mode":"launcher"}}],"gestures":{"enabled":true,"twoFingerVolume":true,"threeFingerBrightness":true,"twoFingerTapPlayPause":true,"edgeSwipeLauncher":true,"flickModes":true}}"#.utf8))
        XCTAssertEqual(v1.version, 1)
        let v2 = Config.migrate(v1)
        XCTAssertEqual(v2.version, Config.currentVersion)
        XCTAssertEqual(v2.leading.map { $0.action?.mode }, ["launcher", "control"])
        XCTAssertFalse(v2.gestures.flickModes)
        XCTAssertEqual(Config.migrate(v2).leading.count, 2)
    }

    func testDefaultConfigIsCurrent() {
        XCTAssertEqual(Config.default.version, Config.currentVersion)
    }

    func testEveryModeIdIsUnique() {
        let ids = ModeRegistry.standard().modes.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ["control", "snake", "pong", "breakout", "flappy", "shooter", "timer", "calc", "emoji", "pet"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }
}
