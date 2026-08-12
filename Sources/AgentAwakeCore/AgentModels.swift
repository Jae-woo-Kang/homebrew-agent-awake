import Foundation

public struct ProcessRecord: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let commandLine: String

    public init(pid: Int32, parentPID: Int32, commandLine: String) {
        self.pid = pid
        self.parentPID = parentPID
        self.commandLine = commandLine
    }
}

public struct AgentPresence: Equatable, Sendable {
    public var cli: Bool
    public var vscode: Bool
    public var app: Bool

    public init(cli: Bool = false, vscode: Bool = false, app: Bool = false) {
        self.cli = cli
        self.vscode = vscode
        self.app = app
    }

    public var isRunning: Bool {
        cli || vscode || app
    }
}

public struct AgentSnapshot: Equatable, Sendable {
    public var codex: AgentPresence
    public var claude: AgentPresence
    public var capturedAt: Date

    public init(
        codex: AgentPresence = AgentPresence(),
        claude: AgentPresence = AgentPresence(),
        capturedAt: Date = Date()
    ) {
        self.codex = codex
        self.claude = claude
        self.capturedAt = capturedAt
    }

    public var hasRunningAgent: Bool {
        codex.isRunning || claude.isRunning
    }
}

public struct RunningApplicationInfo: Equatable, Sendable {
    public let localizedName: String
    public let bundleIdentifier: String
    public let bundlePath: String

    public init(localizedName: String, bundleIdentifier: String, bundlePath: String) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
    }
}
