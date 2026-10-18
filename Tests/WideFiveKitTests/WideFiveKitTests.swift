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
        XCTAssertEqual(AgentTranscripts.claudeProjectNames(for: "/private/tmp/p"), ["-private-tmp-p", "-tmp-p"])
        XCTAssertEqual(AgentTranscripts.claudeProjectNames(for: "/var/x"), ["-var-x", "-private-var-x"])
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
        XCTAssertEqual(AgentTranscripts.codexVerdict(lines: approval, file: file)?.phase, .needsApproval("Approve: rm -rf x"))
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
        func agent(_ id: String, _ kind: Agent.Kind, _ name: String, _ detail: String, host: String?, logo: String?) -> Agent {
            Agent(id: id, kind: kind, name: name, detail: detail, state: .working, color: "#000", logo: logo, icon: "x", hostBundleId: host,
                  focus: .app(bundleId: host ?? "x", window: nil), signal: "cpu")
        }
        let agents = [
            agent("d1", .terminal, "Claude Code", "widefive · Terminal", host: "com.apple.Terminal", logo: "web:claude.ai"),
            agent("d2", .web, "Codex", "Add agent monitor — Codex", host: "com.google.Chrome", logo: "web:chatgpt.com"),
            agent("d3", .terminal, "Gemini CLI", "api · iTerm2", host: "com.googlecode.iterm2", logo: "web:gemini.google.com"),
            agent("d4", .app, "Cursor", "landing-page", host: "com.todesktop.230313mzl4w4u92", logo: "web:cursor.com"),
            agent("d5", .web, "Claude Code", "Claude Code", host: "com.google.Chrome", logo: "web:claude.ai"),
            agent("d6", .app, "ChatGPT", "ChatGPT", host: "com.openai.chat", logo: "web:chatgpt.com"),
        ]
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

final class ProcessScannerTests: XCTestCase {
    func testSeesItself() throws {
        let me = getpid()
        let list = ProcessScanner.list()
        let mine = try XCTUnwrap(list.first { $0.pid == me })
        XCTAssertEqual(mine.ppid, getppid())
        XCTAssertFalse(mine.comm.isEmpty)
        XCTAssertGreaterThan(mine.startTime, 1_600_000_000)
        XCTAssertFalse(ProcessScanner.arguments(me).isEmpty)
        XCTAssertEqual(ProcessScanner.cwd(me), URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path)
        XCTAssertGreaterThan(ProcessScanner.cpuTime(me) ?? 0, 0)
        XCTAssertTrue(ProcessScanner.isAlive(me))
        XCTAssertFalse(ProcessScanner.isAlive(2_000_000_000))
        XCTAssertNotNil(ProcessScanner.path(me))
    }
}

final class AgentMonitorEndToEndTests: XCTestCase {
    /// A process called `claude` sitting in a project whose Claude Code journal ends with a finished reply
    /// must show up as a waiting Claude Code agent, matched to that journal, with no hooks or setup involved.
    func testFakeClaudeProcessIsFoundAndReadFromItsJournal() throws {
        let fm = FileManager.default
        // The kernel reports resolved paths (/private/var/…), so build everything from the resolved folder.
        let root = fm.temporaryDirectory.appendingPathComponent("widefive-e2e-\(UUID().uuidString)").resolvingSymlinksInPath()
        let project = root.appendingPathComponent("my-app")
        let bin = root.appendingPathComponent("bin")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // The fake agent: a symlink named `claude` to /bin/sleep, run from the project folder.
        let exe = bin.appendingPathComponent("claude")
        try fm.createSymbolicLink(at: exe, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = ["300"]
        proc.currentDirectoryURL = project
        try proc.run()
        defer { proc.terminate() }

        // Its journal, in the folder layout Claude Code uses, named from the cwd exactly as the kernel reports it.
        usleep(300_000) // let the child exec so the kernel reports its name and cwd
        let kernelCwd = try XCTUnwrap(ProcessScanner.cwd(proc.processIdentifier))
        XCTAssertTrue(kernelCwd.hasSuffix("/my-app"), kernelCwd)
        let projects = root.appendingPathComponent("projects")
        AgentTranscripts.claudeProjects = projects
        let jdir = projects.appendingPathComponent(AgentTranscripts.claudeProjectNames(for: kernelCwd)[0])
        try fm.createDirectory(at: jdir, withIntermediateDirectories: true)
        let journal = jdir.appendingPathComponent("11111111-2222-3333-4444-555555555555.jsonl")
        let now = ISO8601DateFormatter().string(from: Date())
        try [
            #"{"type":"user","timestamp":"\#(now)","cwd":"\#(project.path)","message":{"role":"user","content":"ship the agent strip"}}"#,
            #"{"type":"assistant","timestamp":"\#(now)","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"Shipped. Anything else?"}]}}"#,
        ].joined(separator: "\n").appending("\n").write(to: journal, atomically: true, encoding: .utf8)

        ClaudeSessions.directory = root.appendingPathComponent("no-sessions")
        let monitor = AgentMonitor()
        var cfg = AgentsConfig()
        cfg.scanBrowsers = false
        monitor.config = cfg
        let agents = monitor.scanNow()
        let me = try XCTUnwrap(agents.first { $0.id == "proc:\(proc.processIdentifier)" }, "agents seen: \(agents.map { "\($0.id) \($0.name)" })")
        XCTAssertEqual(me.name, "Claude Code")
        XCTAssertEqual(me.kind, .terminal)
        XCTAssertEqual(me.signal, "transcript")
        XCTAssertEqual(me.state, .done)
        XCTAssertEqual(me.message, "Shipped. Anything else?")
        XCTAssertTrue(me.detail.hasPrefix("my-app"), me.detail)
        XCTAssertTrue(me.detail.contains("ship the agent strip"), me.detail)

        // A new prompt appended to the journal flips it to working on the next scan.
        usleep(20_000)
        let h = try FileHandle(forWritingTo: journal)
        try h.seekToEnd()
        try h.write(contentsOf: Data(#"{"type":"user","timestamp":"\#(now)","message":{"role":"user","content":"now add tests"}}"#.appending("\n").utf8))
        try h.close()
        let again = monitor.scanNow().first { $0.id == me.id }
        XCTAssertEqual(again?.state, .working)
        XCTAssertEqual(again?.signal, "transcript")
    }
}

final class ClaudeSessionsTests: XCTestCase {
    func entry(_ json: String) -> ClaudeSessions.Entry? { ClaudeSessions.parse(Data(json.utf8)) }

    func testParsesTheRealFileFormat() throws {
        // Verbatim shape of a Claude Code 2.1 ~/.claude/sessions/<pid>.json.
        let e = try XCTUnwrap(entry(#"{"pid":97,"sessionId":"d31b04dc-a220-5dc3-8ffd-02a95eac2017","cwd":"/home/user/widefive","startedAt":1792325879599,"procStart":"350","version":"2.1.302","peerProtocol":1,"kind":"interactive","entrypoint":"cli","name":"widefive-2b","nameSource":"derived","updatedAt":1792325881037,"status":"busy","statusUpdatedAt":1792325881037}"#))
        XCTAssertEqual(e.pid, 97)
        XCTAssertEqual(e.cwd, "/home/user/widefive")
        XCTAssertEqual(e.kind, "interactive")
        XCTAssertFalse(e.nameIsUser)
        XCTAssertEqual(e.statusUpdatedAt?.timeIntervalSince1970 ?? 0, 1792325881.037, accuracy: 0.001)
        XCTAssertEqual(ClaudeSessions.state(of: e).0, .working)
        XCTAssertNil(entry("{}"))
        XCTAssertNil(entry("nope"))
    }

    func testStates() throws {
        let waiting = try XCTUnwrap(entry(#"{"pid":1,"status":"waiting","waitingFor":"input needed","startedAt":1792325879599,"statusUpdatedAt":1792325939599}"#))
        XCTAssertEqual(ClaudeSessions.state(of: waiting).0, .waiting)
        XCTAssertEqual(ClaudeSessions.state(of: waiting).1, "Needs your input")
        let perm = try XCTUnwrap(entry(#"{"pid":1,"status":"waiting","waitingFor":"permission to run Bash","startedAt":1792325879599,"statusUpdatedAt":1792325939599}"#))
        XCTAssertEqual(ClaudeSessions.state(of: perm).1, "Waiting for your permission — permission to run Bash")
        let done = try XCTUnwrap(entry(#"{"pid":1,"status":"idle","startedAt":1792325879599,"statusUpdatedAt":1792325939599}"#))
        XCTAssertEqual(ClaudeSessions.state(of: done).0, .done)
        let fresh = try XCTUnwrap(entry(#"{"pid":1,"status":"idle","startedAt":1792325879599,"statusUpdatedAt":1792325880499}"#))
        XCTAssertEqual(ClaudeSessions.state(of: fresh).0, .idle)
        XCTAssertEqual(ClaudeSessions.state(of: try XCTUnwrap(entry(#"{"pid":1,"status":"shell"}"#))).0, .working)
    }

    /// A real process plus the status file Claude Code would keep for it: waiting → done → working, exactly.
    func testMonitorFollowsTheSessionFile() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("widefive-sess-\(UUID().uuidString)").resolvingSymlinksInPath()
        let project = root.appendingPathComponent("api-server")
        let bin = root.appendingPathComponent("bin")
        let sessions = root.appendingPathComponent("sessions")
        for d in [project, bin, sessions] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }
        let exe = bin.appendingPathComponent("claude")
        try fm.createSymbolicLink(at: exe, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = ["300"]
        proc.currentDirectoryURL = project
        try proc.run()
        defer { proc.terminate() }
        usleep(300_000)
        let pid = proc.processIdentifier
        ClaudeSessions.directory = sessions
        AgentTranscripts.claudeProjects = root.appendingPathComponent("no-projects")
        let file = sessions.appendingPathComponent("\(pid).json")
        let started = Date().addingTimeInterval(-120).timeIntervalSince1970 * 1000
        func write(_ status: String, waitingFor: String? = nil, at: Double) throws {
            var o: [String: Any] = ["pid": Int(pid), "sessionId": "abc", "cwd": project.path, "kind": "interactive", "entrypoint": "cli",
                                    "name": "api-server", "nameSource": "derived", "startedAt": started, "status": status, "statusUpdatedAt": at]
            if let waitingFor { o["waitingFor"] = waitingFor }
            try JSONSerialization.data(withJSONObject: o).write(to: file, options: .atomic)
        }
        let monitor = AgentMonitor()
        var cfg = AgentsConfig()
        cfg.scanBrowsers = false
        monitor.config = cfg
        func me() -> Agent? { monitor.scanNow().first { $0.id == "proc:\(pid)" } }

        try write("waiting", waitingFor: "permission to run Bash", at: started + 60_000)
        var a = try XCTUnwrap(me())
        XCTAssertEqual(a.signal, "session")
        XCTAssertEqual(a.state, .waiting)
        XCTAssertEqual(a.message, "Waiting for your permission — permission to run Bash")
        XCTAssertTrue(a.detail.hasPrefix("api-server"), a.detail)
        XCTAssertTrue(a.needsYou)

        try write("busy", at: started + 70_000)
        a = try XCTUnwrap(me())
        XCTAssertEqual(a.state, .working)
        XCTAssertFalse(a.needsYou)

        try write("idle", at: started + 90_000)
        a = try XCTUnwrap(me())
        XCTAssertEqual(a.state, .done)
        XCTAssertEqual(a.message, "Done — your turn")
        XCTAssertTrue(a.needsYou)

        // The file of a process that has exited is ignored.
        proc.terminate()
        proc.waitUntilExit()
        XCTAssertNil(monitor.scanNow().first { $0.id == "proc:\(pid)" })
    }
}

final class BannerAgentTests: XCTestCase {
    func testBannerMeaning() {
        XCTAssertEqual(AgentMonitor.bannerState("Claude · Fix login bug · Claude needs your permission to use Bash"), .waiting)
        XCTAssertEqual(AgentMonitor.bannerState("Google Chrome · claude.ai · Claude has a question for you"), .waiting)
        XCTAssertEqual(AgentMonitor.bannerState("Claude · Fix login bug · Task complete"), .done)
        XCTAssertEqual(AgentMonitor.bannerState("Google Chrome · chatgpt.com · Codex · Your task is ready"), .done)
    }

    func testUnmatchedWebBannerBecomesItsOwnEntry() throws {
        let tabs = [AppScripting.Tab(bundleId: "com.google.Chrome", window: 1, index: 3, url: "https://claude.ai/code/session_01ABC", title: "Claude Code")]
        let b = NotificationBanners.Banner(id: "n1", app: "Google Chrome", bundleId: "com.google.Chrome", text: "Google Chrome · claude.ai · Fix flaky test · Done")
        let a = try XCTUnwrap(AgentMonitor.agentFromBanner(b, state: .done, tabs: tabs))
        XCTAssertEqual(a.name, "Claude Code")
        XCTAssertEqual(a.state, .done)
        XCTAssertEqual(a.focus, .tab(bundleId: "com.google.Chrome", url: "https://claude.ai/code/session_01ABC", title: "Claude Code"))
        // No tab open: tapping opens the site.
        let noTab = try XCTUnwrap(AgentMonitor.agentFromBanner(b, state: .done, tabs: []))
        XCTAssertEqual(noTab.focus, .url("https://claude.ai/code"))
        // Banners from apps that aren't agents are ignored.
        XCTAssertNil(AgentMonitor.agentFromBanner(NotificationBanners.Banner(id: "n2", app: "Mail", bundleId: "com.apple.mail", text: "Mail · Lunch?"), state: .done, tabs: []))
    }
}

final class TimeBoxTests: XCTestCase {
    func testWithinReturnsFastWorkAndGivesUpOnSlowWork() {
        XCTAssertEqual(AgentMonitor.within(2) { 41 + 1 }, 42)
        let t0 = Date()
        XCTAssertNil(AgentMonitor.within(0.3) { () -> Int in Thread.sleep(forTimeInterval: 3); return 1 })
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1.5)
    }
}

final class AgentDetailTests: XCTestCase {
    let file = URL(fileURLWithPath: "/tmp/x.jsonl")

    func testToolsInPlainWords() {
        XCTAssertEqual(AgentTranscripts.describeTool("Bash", input: ["command": "swift test --parallel\necho done"]), "Running swift test --parallel")
        XCTAssertEqual(AgentTranscripts.describeTool("Edit", input: ["file_path": "/Users/me/app/Sources/Hero.tsx"]), "Editing Hero.tsx")
        XCTAssertEqual(AgentTranscripts.describeTool("Read", input: ["file_path": "/a/b/README.md"]), "Reading README.md")
        XCTAssertEqual(AgentTranscripts.describeTool("Grep", input: ["pattern": "TODO"]), "Searching “TODO”")
        XCTAssertEqual(AgentTranscripts.describeTool("exec_command", input: ["command": ["bash", "-lc", "npm test"]]), "Running npm test")
        XCTAssertEqual(AgentTranscripts.describeTool("exec_command", input: ["cmd": "cargo build"]), "Running cargo build")
        XCTAssertEqual(AgentTranscripts.describeTool("Task", input: ["description": "Find the bug"]), "Subagent: Find the bug")
        XCTAssertEqual(AgentTranscripts.describeTool("mcp__github__create_pr", input: [:]), "Using create pr")
    }

    func testLimitsAndErrors() {
        XCTAssertEqual(AgentTranscripts.classifyProblem("5-hour limit reached ∙ resets 3pm"), .limited(resets: "resets 3pm"))
        XCTAssertEqual(AgentTranscripts.classifyProblem("You've hit your usage limit. Try again in 2 hours."), .limited(resets: "Try again in 2 hours"))
        XCTAssertEqual(AgentTranscripts.classifyProblem("API Error: 429 rate_limit_error"), .limited(resets: nil))
        if case .limited(let r) = AgentTranscripts.classifyProblem("Claude AI usage limit reached|1792339200") { XCTAssertTrue(r?.hasPrefix("resets ") == true, r ?? "nil") }
        else { XCTFail("epoch form not recognised") }
        XCTAssertEqual(AgentTranscripts.classifyProblem("API Error: 500 Internal server error"), .error("API Error: 500 Internal server error"))
    }

    func testClaudeJournalActivityLimitAndBranch() throws {
        let running = [
            #"{"type":"user","timestamp":"2026-10-18T10:00:00Z","gitBranch":"agent-strip","message":{"role":"user","content":"run the tests"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-18T10:00:02Z","gitBranch":"agent-strip","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test"}}]}}"#,
        ]
        let v = try XCTUnwrap(AgentTranscripts.claudeVerdict(lines: running, file: file))
        XCTAssertEqual(v.activity, "Running swift test")
        XCTAssertEqual(v.branch, "agent-strip")
        let limited = running + [
            #"{"type":"user","timestamp":"2026-10-18T10:00:05Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-10-18T10:00:06Z","isApiErrorMessage":true,"message":{"id":"m2","role":"assistant","content":[{"type":"text","text":"5-hour limit reached ∙ resets 3pm"}]}}"#,
        ]
        let l = try XCTUnwrap(AgentTranscripts.claudeVerdict(lines: limited, file: file))
        XCTAssertEqual(l.problem, .limited(resets: "resets 3pm"))
        XCTAssertNil(l.lastText) // the error isn't mistaken for Claude's last reply
    }

    func testCodexActivityAndError() throws {
        let lines = [
            #"{"timestamp":"2026-10-18T10:00:00Z","type":"turn_context","payload":{"cwd":"/a","git":{"branch":"main"}}}"#,
            #"{"timestamp":"2026-10-18T10:00:01Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"npm test\"}","call_id":"c1"}}"#,
        ]
        let v = try XCTUnwrap(AgentTranscripts.codexVerdict(lines: lines, file: file))
        XCTAssertEqual(v.activity, "Running npm test")
        XCTAssertEqual(v.branch, "main")
        let err = lines + [#"{"timestamp":"2026-10-18T10:00:09Z","type":"event_msg","payload":{"type":"error","message":"You've hit your usage limit. Try again in 3 hours."}}"#]
        XCTAssertEqual(try XCTUnwrap(AgentTranscripts.codexVerdict(lines: err, file: file)).problem, .limited(resets: "Try again in 3 hours"))
    }

    func testSessionsAreNumberedPerAgentAndKeepTheirNumbers() {
        func a(_ id: String, _ name: String, _ ago: Double) -> Agent {
            Agent(id: id, kind: .terminal, name: name, detail: "", state: .working, since: Date().addingTimeInterval(-ago), color: "#000", icon: "x",
                  focus: .url("x"), signal: "session")
        }
        let m = AgentMonitor()
        var list = [a("p3", "Claude Code", 10), a("p1", "Claude Code", 300), a("c1", "Codex", 50), a("p2", "Claude Code", 100)]
        m.number(&list)
        let n = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.number) })
        XCTAssertEqual(n["p1"], 1); XCTAssertEqual(n["p2"], 2); XCTAssertEqual(n["p3"], 3); XCTAssertEqual(n["c1"], 1)
        // Session 1 ends: the others keep 2 and 3, and a new one takes the free 1.
        var next = [a("p3", "Claude Code", 10), a("p2", "Claude Code", 100), a("p4", "Claude Code", 1)]
        m.number(&next)
        let n2 = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0.number) })
        XCTAssertEqual(n2["p2"], 2); XCTAssertEqual(n2["p3"], 3); XCTAssertEqual(n2["p4"], 1)
        XCTAssertEqual(next.first { $0.id == "p4" }?.displayName, "Claude Code 1")
    }

    func testMarks() {
        XCTAssertEqual(Agent.Mark.for(name: "Claude Code", appBundleId: nil), .official("claude-code"))
        XCTAssertEqual(Agent.Mark.for(name: "Codex", appBundleId: "com.openai.codex"), .official("codex"))
        XCTAssertEqual(Agent.Mark.for(name: "Gemini CLI", appBundleId: nil), .official("gemini-cli"))
        XCTAssertEqual(Agent.Mark.for(name: "Cursor Agent", appBundleId: nil), .official("cursor"))
        XCTAssertEqual(Agent.Mark.for(name: "Aider", appBundleId: nil), .monogram("A"))
        // Every official icon decodes.
        for key in AgentIcons.keys { XCTAssertNotNil(AgentIcons.image(key), key) }
        for (_, key) in Agent.Mark.officialKeys { XCTAssertNotNil(AgentIcons.image(key), key) }
    }
}

final class GestureTests: XCTestCase {
    func touch(_ id: Int, _ x: CGFloat, _ time: Double, startX: CGFloat? = nil) -> StripTouch {
        StripTouch(id: id, x: x, y: 15, startX: startX ?? x, startTime: time, time: time)
    }

    /// A touch whose end was never delivered (it ended in a mode without gestures) must not turn the next single tap
    /// into a two-finger volume gesture.
    func testLostTouchDoesNotHijackTheNextTap() {
        let g = GestureEngine()
        XCTAssertFalse(g.began(touch(1, 100, 0)))       // long-press that switched modes; its end goes elsewhere
        g.forget(1)
        XCTAssertFalse(g.began(touch(2, 300, 1)))       // a normal tap afterwards
        XCTAssertFalse(g.ended(touch(2, 300, 1.1)))
        // Even if forget() were missed, a stale touch expires.
        XCTAssertFalse(g.began(touch(3, 100, 2)))
        XCTAssertFalse(g.began(touch(4, 300, 9)))
        XCTAssertFalse(g.isClaiming)
    }

    func testTwoFingersStillMeanVolume() {
        let g = GestureEngine()
        var volume: Float?
        g.emit = { if case .volume(let v) = $0 { volume = v } }
        XCTAssertFalse(g.began(touch(1, 100, 0)))
        XCTAssertTrue(g.began(touch(2, 140, 0.05)))
        XCTAssertTrue(g.moved(touch(2, 240, 0.2)))
        XCTAssertNotNil(volume)
        g.reset()
        XCTAssertFalse(g.isClaiming)
    }
}

final class CloudSessionTests: XCTestCase {
    func testMapsSessionsLikeClaudeCodeDoes() {
        let now = ISO8601DateFormatter().string(from: Date())
        let old = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-6 * 3600))
        let json = """
        {"data":[
          {"id":"session_A","title":"Fix login bug","status":"active","worker_status":"running","last_event_at":"\(now)",
           "config":{"sources":[{"type":"git_repository","url":"https://github.com/me/web-app","branch":"fix-login"}]}},
          {"id":"session_B","title":"Add tests","status":"active","worker_status":"requires_action","last_event_at":"\(now)",
           "external_metadata":{"pending_action":{"tool_name":"Bash","description":"Run npm test"}}},
          {"id":"session_C","title":"Docs","status":"active","worker_status":"idle","status_bucket":"completed","last_event_at":"\(now)",
           "external_metadata":{"post_turn_summary":{"summary":"Docs updated and pushed"}}},
          {"id":"session_D","title":"Old","status":"active","worker_status":"idle","status_bucket":"completed","last_event_at":"\(old)"},
          {"id":"session_E","title":"Gone","status":"archived","worker_status":"idle","last_event_at":"\(now)"},
          {"id":"session_F","title":"Broke","status":"active","worker_status":"idle","status_bucket":"failed","last_event_at":"\(now)",
           "external_metadata":{"post_turn_summary":{"status_detail":"API Error: 500"}}},
          {"id":"session_G","title":"Asks","status":"paused","worker_status":"idle","status_bucket":"blocked","last_event_at":"\(now)"}
        ]}
        """
        let list = CloudSessions.parseSessions(Data(json.utf8))
        let byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        XCTAssertEqual(byId["session_A"]?.state, .working)
        XCTAssertEqual(byId["session_A"]?.repo, "web-app")
        XCTAssertEqual(byId["session_A"]?.branch, "fix-login")
        XCTAssertEqual(byId["session_B"]?.state, .waiting)
        XCTAssertEqual(byId["session_B"]?.message, "Run npm test")
        XCTAssertEqual(byId["session_C"]?.state, .done)
        XCTAssertEqual(byId["session_C"]?.message, "Docs updated and pushed")
        XCTAssertNil(byId["session_D"], "finished long ago: not on the bar")
        XCTAssertNil(byId["session_E"], "archived")
        XCTAssertEqual(byId["session_F"]?.state, .failed)
        XCTAssertEqual(byId["session_F"]?.message, "API Error: 500")
        XCTAssertEqual(byId["session_G"]?.state, .waiting)
        XCTAssertTrue(CloudSessions.parseSessions(Data("nope".utf8)).isEmpty)
    }

    func testReadsTheSignInFormat() {
        let ok = CloudSessions.parseToken(Data(#"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1792325879599,"scopes":["user:inference"]}}"#.utf8))
        if case .success(let (t, exp)) = ok {
            XCTAssertEqual(t, "tok")
            XCTAssertEqual(exp?.timeIntervalSince1970 ?? 0, 1792325879.599, accuracy: 0.01)
        } else { XCTFail("not parsed") }
        if case .failure(let s) = CloudSessions.parseToken(Data(#"{"other":{}}"#.utf8)) { XCTAssertEqual(s, .noSignIn) } else { XCTFail() }
        XCTAssertEqual(CloudSessions.pendingAction("Approve deploy"), "Approve deploy")
        XCTAssertEqual(CloudSessions.pendingAction(["tool_name": "Bash"]), "Approve: Bash")
    }
}

final class SessionRecognitionTests: XCTestCase {
    func testDesktopAppAndSDKProcessesAreClaudeCode() {
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: [
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper",
            "/Applications/Claude.app/Contents/Resources/app.asar.unpacked/node_modules/@anthropic-ai/claude-agent-sdk/cli.js",
            "--output-format", "stream-json"], comm: "Claude Helper")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["/Users/me/Library/Application Support/Claude/claude-code/2.1.300/claude", "--print"],
                                                 comm: "claude")?.name, "Claude Code")
        XCTAssertEqual(AgentCatalog.terminalSpec(arguments: ["/Applications/Codex.app/Contents/Resources/codex", "app-server"], comm: "codex")?.name, "Codex")
        XCTAssertNil(AgentCatalog.terminalSpec(arguments: ["/Applications/Claude.app/Contents/MacOS/Claude"], comm: "Claude"))
    }

    /// A session whose turn is over but whose background subagent is still writing is working, not idle.
    func testBackgroundAgentsKeepASessionWorking() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("widefive-bg-\(UUID().uuidString)").resolvingSymlinksInPath()
        let project = root.appendingPathComponent("svc")
        let bin = root.appendingPathComponent("bin")
        let sessions = root.appendingPathComponent("sessions")
        for d in [project, bin, sessions] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(at: bin.appendingPathComponent("claude"), withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let proc = Process()
        proc.executableURL = bin.appendingPathComponent("claude")
        proc.arguments = ["300"]
        proc.currentDirectoryURL = project
        try proc.run()
        defer { proc.terminate() }
        usleep(300_000)
        let pid = proc.processIdentifier
        let cwd = try XCTUnwrap(ProcessScanner.cwd(pid))
        ClaudeSessions.directory = sessions
        let projects = root.appendingPathComponent("projects")
        AgentTranscripts.claudeProjects = projects
        let started = Date().addingTimeInterval(-300).timeIntervalSince1970 * 1000
        let o: [String: Any] = ["pid": Int(pid), "sessionId": "s-bg", "cwd": cwd, "kind": "interactive", "status": "idle",
                                "startedAt": started, "statusUpdatedAt": started + 120_000]
        try JSONSerialization.data(withJSONObject: o).write(to: sessions.appendingPathComponent("\(pid).json"))
        let monitor = AgentMonitor()
        var cfg = AgentsConfig(); cfg.scanBrowsers = false
        monitor.config = cfg
        XCTAssertEqual(monitor.scanNow().first { $0.id == "proc:\(pid)" }?.state, .done)
        // A subagent journal being written right now.
        let sub = projects.appendingPathComponent(AgentTranscripts.claudeProjectNames(for: cwd)[0]).appendingPathComponent("s-bg/subagents")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try "{}\n".write(to: sub.appendingPathComponent("agent-1.jsonl"), atomically: true, encoding: .utf8)
        let a = try XCTUnwrap(monitor.scanNow().first { $0.id == "proc:\(pid)" })
        XCTAssertEqual(a.state, .working)
        XCTAssertEqual(a.activity, "Background agents running")
    }
}
