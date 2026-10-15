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
        XCTAssertEqual(v2.leading.prefix(2).map { $0.action?.mode }, ["launcher", "control"])
        XCTAssertTrue(v2.trailing.contains { $0.kind == "quick" })
        XCTAssertFalse(v2.gestures.flickModes)
        XCTAssertEqual(Config.migrate(v2).leading.count, v2.leading.count)
    }

    func testDefaultConfigIsCurrent() {
        XCTAssertEqual(Config.default.version, Config.currentVersion)
    }

    func testV4ConfigGainsAgentsWidgetBeforeTheFirstTrailingWidget() throws {
        let v4 = try Config.decode(Data(#"{"version":4,"trailing":[{"type":"quick","name":"volume"},{"type":"widget","name":"battery"},{"type":"widget","name":"clock"}]}"#.utf8))
        XCTAssertFalse(v4.hasWidget("agents"))
        let v5 = Config.migrate(v4)
        XCTAssertEqual(v5.version, Config.currentVersion)
        XCTAssertEqual(v5.trailing.map { $0.name }, ["volume", "agents", "battery", "clock"])
        // Idempotent: a config that already has the widget doesn't get a second one.
        XCTAssertEqual(Config.migrate(v5).trailing.count, v5.trailing.count)
    }

    func testAgentsConfigDecodesPartially() throws {
        let c = try Config.decode(Data(#"{"agents":{"idleSeconds":10,"sites":{"app.example.com":"Example"}}}"#.utf8))
        XCTAssertEqual(c.agents.idleSeconds, 10)
        XCTAssertEqual(c.agents.sites["app.example.com"], "Example")
        XCTAssertTrue(c.agents.enabled)
        XCTAssertTrue(c.agents.toast)
        XCTAssertTrue(Config.default.hasWidget("agents"))
    }

    func testEveryModeIdIsUnique() {
        let ids = ModeRegistry.standard().modes.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ["control", "snake", "pong", "breakout", "flappy", "shooter", "timer", "calc", "emoji", "pet", "agents"] {
            XCTAssertTrue(ids.contains(id), id)
        }
    }
}

final class AgentCatalogTests: XCTestCase {
    func testRecognisesTerminalAgentsFromArgv() {
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["claude", "--resume"], comm: "claude")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"], comm: "node")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["/opt/homebrew/lib/node_modules/@openai/codex/bin/codex-aarch64-apple-darwin"], comm: "codex-aarch64-a")?.name, "Codex")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["python3", "-m", "aider", "--model", "x"], comm: "python3")?.name, "Aider")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["node", "/x/gemini-cli/dist/index.js"], comm: "node")?.name, "Gemini CLI")
        XCTAssertNil(AgentCatalog.terminalSpec(arguments: ["node", "/srv/app/server.js"], comm: "node"))
        XCTAssertNil(AgentCatalog.terminalSpec(arguments: ["-zsh"], comm: "zsh"))
        XCTAssertNil(AgentCatalog.terminalSpec(arguments: [], comm: "kernel_task"))
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["/usr/local/bin/myagent", "run"], comm: "myagent", extra: ["myagent": "My Agent"])?.name, "My Agent")
    }

    func testRecognisesDesktopApps() {
        XCTAssertEqual(AgentCatalog.appSpec(bundleId: "com.todesktop.230313mzl4w4u92", name: "Cursor")?.name, "Cursor")
        XCTAssertEqual(AgentCatalog.appSpec(bundleId: "com.unknown.devin", name: "Devin")?.name, "Devin")
        XCTAssertEqual(AgentCatalog.appSpec(bundleId: "com.microsoft.VSCode", name: "Code")?.standalone, false)
        XCTAssertNil(AgentCatalog.appSpec(bundleId: "com.apple.Safari", name: "Safari"))
        XCTAssertEqual(AgentCatalog.appSpec(bundleId: "com.example.bot", name: "Bot", extra: ["com.example.bot": "Bot"])?.name, "Bot")
    }

    func testRecognisesWebAgentsByURL() {
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://claude.ai/code/session_01ABC")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://chatgpt.com/codex/tasks/abc")?.name, "Codex")
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://app.devin.ai/sessions/x")?.name, "Devin")
        XCTAssertNil(AgentCatalog.siteSpec(url: "https://www.google.com/search?q=claude.ai/code"))
        XCTAssertNil(AgentCatalog.siteSpec(url: "chrome://newtab"))
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://app.example.com/agents/1", extra: ["app.example.com/agents": "Example"])?.name, "Example")
        XCTAssertEqual(AgentCatalog.domain("https://www.claude.ai/code"), "claude.ai")
    }

    func testTabTitlesThatNeedYou() {
        let p = AgentCatalog.defaultAttentionTitles
        XCTAssertTrue(AgentCatalog.titleNeedsYou("(1) Codex", patterns: p))
        XCTAssertTrue(AgentCatalog.titleNeedsYou("Claude needs your approval — Claude", patterns: p))
        XCTAssertTrue(AgentCatalog.titleNeedsYou("Waiting for your input · Devin", patterns: p))
        XCTAssertFalse(AgentCatalog.titleNeedsYou("Add agent monitor — Codex", patterns: p))
        XCTAssertFalse(AgentCatalog.titleNeedsYou("", patterns: p))
        XCTAssertTrue(AgentCatalog.titleNeedsYou("done!", patterns: ["^done"]))
    }
}

final class AgentHooksTests: XCTestCase {
    func parse(_ s: String) -> AgentHooks.Event? { AgentHooks.parse(Data(s.utf8)) }

    func testClaudeEvents() throws {
        let n = try XCTUnwrap(parse(#"{"kind":"claude","pid":1,"tty":"ttys003","time":1700000000,"event":{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"/Users/me/proj","session_id":"s1"}}"#))
        XCTAssertEqual(n.state, .waiting)
        XCTAssertEqual(n.message, "Claude needs your permission to use Bash")
        XCTAssertEqual(n.cwd, "/Users/me/proj")
        XCTAssertEqual(n.tty, "ttys003")
        XCTAssertEqual(n.sessionId, "s1")
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"??","time":1,"event":{"hook_event_name":"Stop"}}"#)?.state, .waiting)
        XCTAssertNil(parse(#"{"kind":"claude","pid":1,"tty":"??","time":1,"event":{"hook_event_name":"Stop"}}"#)?.tty)
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"","time":1,"event":{"hook_event_name":"UserPromptSubmit"}}"#)?.state, .working)
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"","time":1,"event":{"hook_event_name":"PreToolUse","tool_name":"Bash"}}"#)?.state, .working)
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"","time":1,"event":{"hook_event_name":"SessionStart"}}"#)?.state, .idle)
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"","time":1,"event":{"hook_event_name":"SessionEnd"}}"#)?.ended, true)
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"tty":"","time":1,"event":{"hook_event_name":"Notification","notification_type":"idle_prompt"}}"#)?.message, "Waiting for your next prompt")
    }

    func testCodexAndCursorEvents() {
        let c = parse(#"{"kind":"codex","pid":2,"tty":"ttys001","time":1,"event":{"type":"agent-turn-complete","turn-id":"t","last-assistant-message":"Done.
Tests pass."}}"#)
        XCTAssertEqual(c?.state, .waiting)
        XCTAssertEqual(c?.message, "Done. Tests pass.")
        XCTAssertEqual(parse(#"{"kind":"cursor","pid":3,"tty":"","time":1,"event":{"hook_event_name":"stop","status":"completed","workspace_roots":["/Users/me/app"]}}"#)?.cwd, "/Users/me/app")
        XCTAssertEqual(parse(#"{"kind":"cursor","pid":3,"tty":"","time":1,"event":{"hook_event_name":"beforeSubmitPrompt"}}"#)?.state, .working)
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse(#"{"kind":"claude"}"#))
        XCTAssertEqual(parse(#"{"kind":"claude","pid":1,"time":1,"event":null}"#)?.state, .working)
    }

    func testClaudeSettingsMergeIsIdempotentAndReversible() throws {
        let existing: [String: Any] = ["model": "opus", "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let once = AgentHooks.claudeSettings(adding: "/Users/me/.widefive/bin/widefive-agent-hook", to: existing)
        let twice = AgentHooks.claudeSettings(adding: "/Users/me/.widefive/bin/widefive-agent-hook", to: once)
        let hooks = try XCTUnwrap(twice["hooks"] as? [String: Any])
        XCTAssertEqual(twice["model"] as? String, "opus")
        for event in AgentHooks.claudeEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            let ours = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.filter { ($0["command"] as? String)?.contains("widefive-agent-hook") == true }
            XCTAssertEqual(ours.count, 1, event)
        }
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2) // the user's "say done" group survived
        let removed = AgentHooks.claudeSettings(removingFrom: twice)
        let rh = try XCTUnwrap(removed["hooks"] as? [String: Any])
        XCTAssertEqual(rh.keys.sorted(), ["Stop"])
        XCTAssertEqual(((rh["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String, "say done")
        XCTAssertNil(AgentHooks.claudeSettings(removingFrom: AgentHooks.claudeSettings(adding: "/x", to: [:]))["hooks"])
    }

    func testCodexConfigGetsNotifyAtTheTop() {
        let (out, _) = AgentHooks.codexConfig(adding: "/x/widefive-agent-hook", to: "model = \"o3\"\n[mcp_servers.a]\ncommand = \"b\"\n")
        XCTAssertTrue(out.hasPrefix("# widefive"))
        XCTAssertTrue(out.contains("notify = [\"/x/widefive-agent-hook\", \"codex\"]\nmodel = \"o3\""))
        XCTAssertEqual(AgentHooks.codexConfig(removingFrom: out), "model = \"o3\"\n[mcp_servers.a]\ncommand = \"b\"\n")
        let (same, note) = AgentHooks.codexConfig(adding: "/x/widefive-agent-hook", to: "notify = [\"other\"]\n")
        XCTAssertEqual(same, "notify = [\"other\"]\n")
        XCTAssertTrue(note.contains("already"))
        XCTAssertEqual(AgentHooks.codexConfig(adding: "/x/widefive-agent-hook", to: out).0, out)
    }

    func testCursorHooksMerge() throws {
        let once = AgentHooks.cursorHooks(adding: "/x/widefive-agent-hook", to: ["hooks": ["stop": [["command": "mine"]]]])
        let twice = AgentHooks.cursorHooks(adding: "/x/widefive-agent-hook", to: once)
        let hooks = try XCTUnwrap(twice["hooks"] as? [String: Any])
        XCTAssertEqual(twice["version"] as? Int, 1)
        XCTAssertEqual((hooks["stop"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((hooks["beforeSubmitPrompt"] as? [[String: Any]])?.count, 1)
        let removed = AgentHooks.cursorHooks(removingFrom: twice)
        XCTAssertEqual(((removed["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])?.first?["command"] as? String, "mine")
        XCTAssertNil((removed["hooks"] as? [String: Any])?["beforeSubmitPrompt"])
    }
}
