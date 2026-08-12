import XCTest
@testable import AgentAwakeCore

final class AgentProcessClassifierTests: XCTestCase {
    func testProcessParserKeepsFullCommandLine() {
        let output = """
          101     1 /opt/homebrew/bin/codex exec fix the build
          202   101 /bin/zsh -l
        """

        XCTAssertEqual(
            ProcessListParser.parse(output),
            [
                ProcessRecord(pid: 101, parentPID: 1, commandLine: "/opt/homebrew/bin/codex exec fix the build"),
                ProcessRecord(pid: 202, parentPID: 101, commandLine: "/bin/zsh -l"),
            ]
        )
    }

    func testClassifiesStandaloneCLIs() {
        let records = [
            ProcessRecord(pid: 10, parentPID: 1, commandLine: "/opt/homebrew/bin/codex exec refactor"),
            ProcessRecord(pid: 11, parentPID: 1, commandLine: "/Users/me/.local/bin/claude"),
        ]

        let snapshot = AgentProcessClassifier.classify(processes: records)

        XCTAssertEqual(snapshot.codex, AgentPresence(cli: true))
        XCTAssertEqual(snapshot.claude, AgentPresence(cli: true))
    }

    func testClassifiesCodexBackendUnderVSCode() {
        let records = [
            ProcessRecord(
                pid: 100,
                parentPID: 1,
                commandLine: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"
            ),
            ProcessRecord(
                pid: 101,
                parentPID: 100,
                commandLine: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
            ),
            ProcessRecord(
                pid: 102,
                parentPID: 101,
                commandLine: "/Users/me/.vscode/extensions/openai.chatgpt-1.2.3/bin/codex app-server"
            ),
        ]

        let snapshot = AgentProcessClassifier.classify(processes: records)

        XCTAssertFalse(snapshot.codex.cli)
        XCTAssertTrue(snapshot.codex.vscode)
    }

    func testClassifiesClaudeIDEProcess() {
        let records = [
            ProcessRecord(
                pid: 200,
                parentPID: 1,
                commandLine: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron"
            ),
            ProcessRecord(
                pid: 201,
                parentPID: 200,
                commandLine: "/Users/me/.local/bin/claude --ide"
            ),
        ]

        let snapshot = AgentProcessClassifier.classify(processes: records)

        XCTAssertFalse(snapshot.claude.cli)
        XCTAssertTrue(snapshot.claude.vscode)
    }

    func testClassifiesDesktopAppsWithoutMarkingCLI() {
        let records = [
            ProcessRecord(
                pid: 300,
                parentPID: 1,
                commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server"
            ),
            ProcessRecord(
                pid: 301,
                parentPID: 1,
                commandLine: "/Applications/Claude.app/Contents/MacOS/Claude"
            ),
        ]

        let apps = [
            RunningApplicationInfo(
                localizedName: "Codex",
                bundleIdentifier: "com.openai.codex",
                bundlePath: "/Applications/Codex.app"
            ),
            RunningApplicationInfo(
                localizedName: "Claude",
                bundleIdentifier: "com.anthropic.claudefordesktop",
                bundlePath: "/Applications/Claude.app"
            ),
        ]

        let snapshot = AgentProcessClassifier.classify(processes: records, runningApplications: apps)

        XCTAssertEqual(snapshot.codex, AgentPresence(app: true))
        XCTAssertEqual(snapshot.claude, AgentPresence(app: true))
    }

    func testDoesNotMatchSimilarExecutableNames() {
        let records = [
            ProcessRecord(pid: 400, parentPID: 1, commandLine: "/usr/local/bin/codex-helper"),
            ProcessRecord(pid: 401, parentPID: 1, commandLine: "/usr/local/bin/claude-monitor"),
        ]

        let snapshot = AgentProcessClassifier.classify(processes: records)

        XCTAssertFalse(snapshot.hasRunningAgent)
    }
}
