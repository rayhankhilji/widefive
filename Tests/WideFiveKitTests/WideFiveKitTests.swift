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
        XCTAssertNil(AgentCatalog.siteSpec(url: "https://claude.ai/chat/abc"))
        XCTAssertNil(AgentCatalog.siteSpec(url: "https://notclaude.ai/code"))
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://www.claude.ai/code?x=1")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.siteSpec(url: "https://jules.google.com/task/1")?.name, "Jules")
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
        let c = parse(#"{"kind":"codex","pid":2,"tty":"ttys001","time":1,"event":{"type":"agent-turn-complete","turn-id":"t","last-assistant-message":"Done.\nTests pass."}}"#)
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
        XCTAssertNil(AgentHooks.claudeSettings(removingFrom: AgentHooks.claudeSettings(adding: "/x/widefive-agent-hook", to: [:]))["hooks"])
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

final class AgentTranscriptTests: XCTestCase {
    let file = URL(fileURLWithPath: "/tmp/x.jsonl")

    func testClaudeProjectFolderNames() {
        XCTAssertEqual(AgentTranscripts.claudeProjectNames(for: "/Users/me/code/app"), ["-Users-me-code-app"])
        XCTAssertEqual(AgentTranscripts.claudeProjectNames(for: "/Users/me/.config/x_y"), ["-Users-me--config-x-y", "-Users-me-.config-x_y"])
    }

    func testClaudeTurnDoneAndToolPending() throws {
        let lines = [
            #"{"type":"summary","summary":"Add the agent strip","leafUuid":"x"}"#,
            #"{"type":"user","timestamp":"2026-10-18T10:00:00.000Z","cwd":"/p","sessionId":"s","isSidechain":false,"message":{"role":"user","content":"add the agent strip to the bar"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-18T10:00:05.000Z","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Sure, let me look."}]}}"#,
            #"{"type":"assistant","timestamp":"2026-10-18T10:00:06.000Z","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test"}}]}}"#,
        ]
        let pending = try XCTUnwrap(AgentTranscripts.claudeVerdict(lines: lines, file: file))
        XCTAssertEqual(pending.phase, .toolPending("Bash"))
        XCTAssertEqual(pending.title, "Add the agent strip")
        XCTAssertEqual(pending.lastText, "Sure, let me look.")
        XCTAssertEqual(pending.at.timeIntervalSince1970, 1792317606, accuracy: 1)

        let result = lines + [#"{"type":"user","timestamp":"2026-10-18T10:00:09.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"toolUseResult":{"stdout":"ok"}}"#]
        XCTAssertEqual(AgentTranscripts.claudeVerdict(lines: result, file: file)?.phase, .working)

        let done = result + [#"{"type":"assistant","timestamp":"2026-10-18T10:00:12.000Z","message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"All tests pass.\n"}]}}"#,
                             #"{"type":"system","subtype":"turn_duration","durationMs":12000}"#,
                             #"{"type":"file-history-snapshot","messageId":"m2"}"#]
        let v = try XCTUnwrap(AgentTranscripts.claudeVerdict(lines: done, file: file))
        XCTAssertEqual(v.phase, .turnDone)
        XCTAssertEqual(v.lastText, "All tests pass.")
        // A trailing half-written line is ignored.
        XCTAssertEqual(AgentTranscripts.claudeVerdict(lines: done + [#"{"type":"user","timest"#], file: file)?.phase, .turnDone)
        // Sidechain (subagent) and meta lines don't count.
        XCTAssertEqual(AgentTranscripts.claudeVerdict(lines: done + [#"{"type":"user","isSidechain":true,"message":{"role":"user","content":"x"}}"#, #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<meta>"}}"#], file: file)?.phase, .turnDone)
        XCTAssertNil(AgentTranscripts.claudeVerdict(lines: ["not json", ""], file: file))
    }

    func testClaudeTitleFromFirstPrompt() {
        let lines = [#"{"type":"user","timestamp":"2026-10-18T10:00:00Z","message":{"role":"user","content":"fix the failing test"}}"#,
                     #"{"type":"assistant","timestamp":"2026-10-18T10:00:05Z","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Done."}]}}"#]
        let v = AgentTranscripts.claudeVerdict(lines: lines, file: file)
        XCTAssertEqual(v?.title, "fix the failing test")
        XCTAssertEqual(v?.phase, .turnDone)
    }

    func testCodexRollout() throws {
        XCTAssertEqual(AgentTranscripts.codexCwd(firstLine: #"{"timestamp":"t","type":"session_meta","payload":{"id":"s","cwd":"/Users/me/app","cli_version":"0.50"}}"#), "/Users/me/app")
        XCTAssertEqual(AgentTranscripts.codexCwd(firstLine: #"{"id":"s","timestamp":"t","cwd":"/legacy","instructions":null}"#), "/legacy")
        XCTAssertNil(AgentTranscripts.codexCwd(firstLine: "nope"))
        let lines = [
            #"{"timestamp":"2026-10-18T10:00:00.000Z","type":"session_meta","payload":{"id":"s","cwd":"/Users/me/app"}}"#,
            #"{"timestamp":"2026-10-18T10:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"refactor the logger"}}"#,
            #"{"timestamp":"2026-10-18T10:00:01.500Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-10-18T10:00:03.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{}","call_id":"c1"}}"#,
        ]
        let pending = try XCTUnwrap(AgentTranscripts.codexVerdict(lines: lines, file: file))
        XCTAssertEqual(pending.phase, .toolPending("exec_command"))
        XCTAssertEqual(pending.title, "refactor the logger")
        let output = lines + [#"{"timestamp":"2026-10-18T10:00:04.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"ok"}}"#]
        XCTAssertEqual(AgentTranscripts.codexVerdict(lines: output, file: file)?.phase, .working)
        let done = output + [#"{"timestamp":"2026-10-18T10:00:08.000Z","type":"event_msg","payload":{"type":"agent_message","message":"Logger refactored."}}"#,
                             #"{"timestamp":"2026-10-18T10:00:08.100Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Logger refactored.","duration_ms":7000}}"#,
                             #"{"timestamp":"2026-10-18T10:00:08.200Z","type":"event_msg","payload":{"type":"token_count","info":{}}}"#]
        let v = try XCTUnwrap(AgentTranscripts.codexVerdict(lines: done, file: file))
        XCTAssertEqual(v.phase, .turnDone)
        XCTAssertEqual(v.lastText, "Logger refactored.")
        let approval = done + [#"{"timestamp":"2026-10-18T10:00:20.000Z","type":"event_msg","payload":{"type":"exec_approval_request","call_id":"c2","command":["rm","-rf","x"]}}"#]
        XCTAssertEqual(AgentTranscripts.codexVerdict(lines: approval, file: file)?.phase, .needsApproval("exec approval request"))
    }

    func testTailLinesReadsOnlyCompleteTrailingLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widefive-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("t.jsonl")
        let body = (0..<200).map { "{\"n\":\($0),\"pad\":\"\(String(repeating: "x", count: 100))\"}" }.joined(separator: "\n") + "\n"
        try body.write(to: f, atomically: true, encoding: .utf8)
        let all = try XCTUnwrap(AgentTranscripts.tailLines(f))
        XCTAssertEqual(all.count, 200)
        let tail = try XCTUnwrap(AgentTranscripts.tailLines(f, bytes: 1000))
        XCTAssertLessThan(tail.count, 12)
        XCTAssertEqual(tail.last, "{\"n\":199,\"pad\":\"\(String(repeating: "x", count: 100))\"}")
        XCTAssertTrue(tail.first!.hasPrefix("{\"n\":"))

        // A real Claude-style project folder is found by cwd and modification time.
        let projects = dir.appendingPathComponent("projects")
        AgentTranscripts.claudeProjects = projects
        let cwd = "/Users/me/code/app"
        let pdir = projects.appendingPathComponent("-Users-me-code-app")
        try FileManager.default.createDirectory(at: pdir, withIntermediateDirectories: true)
        try "{}\n".write(to: pdir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AgentTranscripts.claudeTranscripts(cwd: cwd, since: Date().addingTimeInterval(-60)).count, 1)
        XCTAssertEqual(AgentTranscripts.claudeTranscripts(cwd: cwd, since: Date().addingTimeInterval(60)).count, 0)
        XCTAssertEqual(AgentTranscripts.claudeTranscripts(cwd: "/elsewhere", since: .distantPast).count, 0)

        // Codex: day folders are walked from `since` to today.
        let sessions = dir.appendingPathComponent("sessions")
        AgentTranscripts.codexSessions = sessions
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        let today = sessions.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: today, withIntermediateDirectories: true)
        try #"{"timestamp":"t","type":"session_meta","payload":{"id":"s","cwd":"/Users/me/app"}}"#.write(to: today.appendingPathComponent("rollout-2026-10-18T10-00-00-abc.jsonl"), atomically: true, encoding: .utf8)
        let found = AgentTranscripts.codexTranscripts(since: Date().addingTimeInterval(-3600))
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(AgentTranscripts.codexCwd(file: found[0]), "/Users/me/app")
    }
}

final class BannerMatchTests: XCTestCase {
    func testBannerMatchesTheRightAgent() {
        let agents = AgentMonitor.demoList()
        let hosts = ["d1": "Terminal", "d2": "Google Chrome", "d3": "iTerm2", "d4": "Cursor", "d5": "Google Chrome", "d6": "ChatGPT"]
        func m(_ app: String?, _ text: String, bundle: String? = nil) -> String? {
            AgentMonitor.match(banner: NotificationBanners.Banner(id: "1", app: app, bundleId: bundle, text: text), agents: agents, hostNames: hosts).map { agents[$0].id }
        }
        XCTAssertEqual(m("Google Chrome", "Google Chrome · claude.ai · Claude Code · Your session needs input"), "d5")
        XCTAssertEqual(m("Google Chrome", "Google Chrome · chatgpt.com · Codex · Task complete: Add agent monitor"), "d2")
        XCTAssertEqual(m("Cursor", "Cursor · Agent finished in landing-page"), "d4")
        XCTAssertEqual(m("iTerm2", "iTerm2 · Gemini CLI · done"), "d3")
        XCTAssertEqual(m("Terminal", "Terminal · Bell in widefive — claude"), "d1")
        XCTAssertEqual(m(nil, "ChatGPT · Your response is ready", bundle: "com.openai.chat"), "d6")
        XCTAssertNil(m("Mail", "Mail · New message from Bob"))
        XCTAssertNil(m("Slack", "Slack · hey"))
    }
}
