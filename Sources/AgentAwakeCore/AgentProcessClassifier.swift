import Foundation

public enum AgentProcessClassifier {
    private static let vscodeMarkers = [
        "/visual studio code.app/",
        "/code helper",
        "/code - insiders.app/",
        "/code-insiders",
        "/vscode-server/",
        "/.vscode/extensions/",
        "/.vscode-insiders/extensions/",
    ]

    private static let codexExtensionMarkers = [
        "/openai.chatgpt-",
        "/openai.codex-",
        "codex app-server",
        "codex app_server",
    ]

    private static let claudeExtensionMarkers = [
        "/anthropic.claude-code-",
        "/anthropic.claude-",
        "/.claude/ide/",
        "claude --ide",
        "claude ide",
    ]

    public static func classify(
        processes: [ProcessRecord],
        runningApplications: [RunningApplicationInfo] = [],
        capturedAt: Date = Date()
    ) -> AgentSnapshot {
        let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var codex = AgentPresence()
        var claude = AgentPresence()

        for app in runningApplications {
            let name = app.localizedName.lowercased()
            let bundleID = app.bundleIdentifier.lowercased()
            let path = app.bundlePath.lowercased()

            if name == "codex" || bundleID.contains("openai.codex") || path.contains("/codex.app") {
                codex.app = true
            }

            if name == "claude" || bundleID.contains("anthropic.claude") || path.contains("/claude.app") {
                claude.app = true
            }
        }

        for process in processes {
            let command = process.commandLine.lowercased()
            let ancestry = ancestorCommandLines(for: process, processByPID: processByPID)
            let isVSCodeContext = containsAny(command, markers: vscodeMarkers)
                || ancestry.contains(where: { containsAny($0, markers: vscodeMarkers) })

            let codexAppProcess = command.contains("/codex.app/contents/")
            let codexExtensionProcess = containsAny(command, markers: codexExtensionMarkers)
                && (isVSCodeContext || command.contains("/.vscode"))
            let codexExecutable = hasExecutable(named: "codex", in: command)

            if codexAppProcess {
                codex.app = true
            } else if codexExtensionProcess || (codexExecutable && isVSCodeContext) {
                codex.vscode = true
            } else if codexExecutable {
                codex.cli = true
            }

            let claudeAppProcess = command.contains("/claude.app/contents/")
            let claudeExtensionProcess = containsAny(command, markers: claudeExtensionMarkers)
                && (isVSCodeContext || command.contains("/.vscode") || command.contains("/.claude/ide/"))
            let claudeExecutable = hasExecutable(named: "claude", in: command)

            if claudeAppProcess {
                claude.app = true
            } else if claudeExtensionProcess || (claudeExecutable && isVSCodeContext) {
                claude.vscode = true
            } else if claudeExecutable {
                claude.cli = true
            }
        }

        return AgentSnapshot(codex: codex, claude: claude, capturedAt: capturedAt)
    }

    private static func ancestorCommandLines(
        for process: ProcessRecord,
        processByPID: [Int32: ProcessRecord]
    ) -> [String] {
        var result: [String] = []
        var nextPID = process.parentPID
        var visited: Set<Int32> = [process.pid]

        for _ in 0..<8 {
            guard nextPID > 0,
                  !visited.contains(nextPID),
                  let parent = processByPID[nextPID] else {
                break
            }
            visited.insert(nextPID)
            result.append(parent.commandLine.lowercased())
            nextPID = parent.parentPID
        }

        return result
    }

    private static func containsAny(_ value: String, markers: [String]) -> Bool {
        markers.contains(where: value.contains)
    }

    private static func hasExecutable(named expectedName: String, in commandLine: String) -> Bool {
        guard let firstToken = commandLine.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }

        let executable = String(firstToken)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return URL(fileURLWithPath: executable).lastPathComponent.lowercased() == expectedName
    }
}
