import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "꺼짐"
    @Published private(set) var isClosedLidEnabled = false
    @Published private(set) var isClosedLidTransitioning = false
    @Published private(set) var closedLidStatusMessage = "꺼짐"
    @Published private(set) var lastError: String?

    let batteryFloor = 20
    let maximumDurationHours = 12

    private var assertionID: IOPMAssertionID = 0
    private var guardianProcess: Process?
    private var guardianErrorPipe: Pipe?
    private var heartbeatTimer: Timer?
    private var leaseDirectory: URL?
    private var expectedGuardianStop = false
    private var guardianDidActivate = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        heartbeatTimer?.invalidate()
    }

    /// The primary toggle only creates a user-level IOKit assertion. It must
    /// never launch an authorization prompt or another process because doing so
    /// dismisses a menu bar window on macOS.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    func enable() {
        guard !isEnabled else { return }

        lastError = nil
        do {
            try createPowerAssertion()
            isEnabled = true
            statusMessage = "켜짐"
        } catch {
            isEnabled = false
            statusMessage = "켜지지 않음"
            lastError = error.localizedDescription
        }
    }

    func disable() {
        guard isEnabled || assertionID != 0 else { return }

        lastError = nil
        disableClosedLidProtection()
        releasePowerAssertion()
        isEnabled = false
        statusMessage = "꺼짐"
    }

    /// Closed-lid support is deliberately separate from the primary toggle.
    /// This optional path requires administrator approval and may temporarily
    /// dismiss the menu window while the system authorization UI has focus.
    func setClosedLidEnabled(_ enabled: Bool) {
        if enabled {
            enableClosedLidProtection()
        } else {
            disableClosedLidProtection()
        }
    }

    func enableClosedLidProtection() {
        guard isEnabled else {
            lastError = "먼저 Mac 잠자기 방지를 켜세요."
            return
        }
        guard !isClosedLidEnabled, !isClosedLidTransitioning else { return }

        lastError = nil
        isClosedLidTransitioning = true
        closedLidStatusMessage = "관리자 승인을 기다리는 중…"

        do {
            let lease = try createLeaseDirectory()
            leaseDirectory = lease
            expectedGuardianStop = false
            guardianDidActivate = false
            try launchGuardian(leaseDirectory: lease)
            startHeartbeat()
        } catch {
            finishGuardianSetupFailure(error.localizedDescription)
        }
    }

    func disableClosedLidProtection() {
        guard guardianProcess != nil || isClosedLidEnabled || isClosedLidTransitioning else {
            isClosedLidEnabled = false
            isClosedLidTransitioning = false
            closedLidStatusMessage = "꺼짐"
            return
        }

        expectedGuardianStop = true
        writeStopSignal()
        isClosedLidEnabled = false
        isClosedLidTransitioning = guardianProcess?.isRunning == true
        closedLidStatusMessage = isClosedLidTransitioning ? "안전하게 해제하는 중…" : "꺼짐"

        if guardianProcess?.isRunning != true {
            finishGuardianStop(errorMessage: nil)
        }
    }

    func shutdown() {
        disableClosedLidProtection()
        releasePowerAssertion()
        isEnabled = false
    }

    private func createPowerAssertion() throws {
        guard assertionID == 0 else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AgentAwake keep-awake toggle" as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            throw KeepAwakeError.powerAssertionFailed(code: result)
        }
        assertionID = newAssertionID
    }

    private func releasePowerAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func createLeaseDirectory() throws -> URL {
        let uid = getuid()
        let directory = URL(
            fileURLWithPath: "/private/var/tmp",
            isDirectory: true
        ).appendingPathComponent("agentawake.\(uid).\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("starting\n".utf8).write(to: directory.appendingPathComponent("heartbeat"))
        try Data().write(to: directory.appendingPathComponent("state"))
        return directory
    }

    private func launchGuardian(leaseDirectory: URL) throws {
        guard let scriptURL = Bundle.module.url(
            forResource: "agentawake-guardian",
            withExtension: "sh"
        ) else {
            throw KeepAwakeError.guardianMissing
        }

        let commandArguments = [
            "/bin/bash",
            scriptURL.path,
            leaseDirectory.path,
            String(ProcessInfo.processInfo.processIdentifier),
            String(getuid()),
            String(batteryFloor),
            String(maximumDurationHours * 60 * 60),
        ]
        let shellCommand = commandArguments.map(Self.shellQuote).joined(separator: " ")
        let appleScript = "do shell script \(Self.appleScriptQuote(shellCommand)) with administrator privileges"

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        guardianProcess = process
        guardianErrorPipe = errorPipe
        do {
            try process.run()
        } catch {
            guardianProcess = nil
            guardianErrorPipe = nil
            throw KeepAwakeError.guardianLaunchFailed(error.localizedDescription)
        }
    }

    private func startHeartbeat() {
        writeHeartbeat()
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(heartbeatTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func heartbeatTick() {
        if let guardianProcess, !guardianProcess.isRunning {
            let data = guardianErrorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let rawMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = rawMessage?.isEmpty == false ? rawMessage : nil
            let failedUnexpectedly = !expectedGuardianStop && guardianProcess.terminationStatus != 0
            finishGuardianStop(errorMessage: failedUnexpectedly ? message : nil)
            return
        }

        writeHeartbeat()

        guard let leaseDirectory else { return }
        let stateURL = leaseDirectory.appendingPathComponent("state")
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else { return }

        if state.contains("state=active") {
            guardianDidActivate = true
            isClosedLidEnabled = true
            isClosedLidTransitioning = false
            closedLidStatusMessage = "켜짐"
        }
    }

    @objc private func heartbeatTimerFired() {
        heartbeatTick()
    }

    @objc private func applicationWillTerminate() {
        shutdown()
    }

    private func writeHeartbeat() {
        guard let leaseDirectory else { return }
        let heartbeat = leaseDirectory.appendingPathComponent("heartbeat")
        let value = "\(Date().timeIntervalSince1970)\n"
        try? Data(value.utf8).write(to: heartbeat, options: .atomic)
    }

    private func writeStopSignal() {
        guard let leaseDirectory else { return }
        let stop = leaseDirectory.appendingPathComponent("stop")
        try? Data("stop\n".utf8).write(to: stop, options: .atomic)
    }

    private func finishGuardianStop(errorMessage: String?) {
        let guardianWasActive = guardianDidActivate || guardianStateShowsActivation()
        let exitReason = guardianExitReason()

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guardianProcess = nil
        guardianErrorPipe = nil
        isClosedLidEnabled = false

        if expectedGuardianStop {
            closedLidStatusMessage = "꺼짐"
        } else if guardianWasActive, Self.requiresFullSafetyStop(exitReason) {
            releasePowerAssertion()
            isEnabled = false
            statusMessage = exitReason ?? "안전장치가 잠자기 방지를 해제함"
            closedLidStatusMessage = "안전장치에 의해 꺼짐"
        } else {
            closedLidStatusMessage = "켜지지 않음"
            lastError = Self.closedLidFailureMessage(errorMessage)
        }

        isClosedLidTransitioning = false
        expectedGuardianStop = false
        guardianDidActivate = false
        cleanLeaseDirectory()
    }

    private func finishGuardianSetupFailure(_ message: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guardianProcess = nil
        guardianErrorPipe = nil
        expectedGuardianStop = false
        guardianDidActivate = false
        isClosedLidEnabled = false
        isClosedLidTransitioning = false
        closedLidStatusMessage = "켜지지 않음"
        lastError = Self.closedLidFailureMessage(message)
        cleanLeaseDirectory()
    }

    private func guardianStateShowsActivation() -> Bool {
        guard let leaseDirectory else { return false }
        let stateURL = leaseDirectory.appendingPathComponent("state")
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return false
        }
        return state.contains("activated=1")
    }

    private func guardianExitReason() -> String? {
        guard let leaseDirectory else { return nil }
        let stateURL = leaseDirectory.appendingPathComponent("state")
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8),
              let reasonLine = state.split(separator: "\n").first(where: { $0.hasPrefix("reason=") }) else {
            return nil
        }
        return String(reasonLine.dropFirst("reason=".count))
    }

    private func cleanLeaseDirectory() {
        if let leaseDirectory {
            try? FileManager.default.removeItem(at: leaseDirectory)
        }
        leaseDirectory = nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func requiresFullSafetyStop(_ reason: String?) -> Bool {
        guard let reason else { return false }
        return reason.contains("배터리")
            || reason.contains("최대 유지 시간")
            || reason.contains("발열")
            || reason.contains("앱 응답")
    }

    private static func closedLidFailureMessage(_ message: String?) -> String {
        if let message,
           message.localizedCaseInsensitiveContains("User canceled")
            || message.localizedCaseInsensitiveContains("-128") {
            return "관리자 승인이 취소되었습니다. 기본 잠자기 방지는 계속 켜져 있습니다."
        }
        return "덮개 닫힘 모드는 켜지지 않았습니다. 기본 잠자기 방지는 계속 켜져 있습니다."
    }
}

private enum KeepAwakeError: LocalizedError {
    case powerAssertionFailed(code: IOReturn)
    case guardianMissing
    case guardianLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .powerAssertionFailed(let code):
            return "macOS 잠자기 방지 요청에 실패했습니다 (오류 \(code))."
        case .guardianMissing:
            return "덮개 닫힘 안전 가디언을 앱 번들에서 찾지 못했습니다."
        case .guardianLaunchFailed(let message):
            return "안전 가디언을 시작하지 못했습니다: \(message)"
        }
    }
}
