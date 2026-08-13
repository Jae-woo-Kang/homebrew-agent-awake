import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isRequestedEnabled = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var statusMessage = "꺼짐"
    @Published private(set) var lastError: String?

    let batteryFloor = 20
    let maximumDurationHours = 12

    private let helperVersion = "1"
    private let helperStatusURL = URL(
        fileURLWithPath: "/private/var/run/agentawake-helper/status"
    )

    private var assertionID: IOPMAssertionID = 0
    private var installerProcess: Process?
    private var installerErrorPipe: Pipe?
    private var heartbeatTimer: Timer?
    private var leaseDirectory: URL?
    private var activationStartedAt: Date?
    private var expectedHelperStop = false

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

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    func enable() {
        guard !isEnabled, !isTransitioning, installerProcess == nil else { return }

        lastError = nil
        isRequestedEnabled = true
        isTransitioning = true
        expectedHelperStop = false
        activationStartedAt = Date()

        do {
            try createPowerAssertion()
            leaseDirectory = try createLeaseDirectory()

            if helperIsReady() {
                statusMessage = "전원 도우미 연결 중…"
            } else {
                statusMessage = "최초 1회 관리자 승인을 기다리는 중…"
                try launchHelperInstaller()
            }
            startHeartbeat()
        } catch {
            finishEnableFailure(error.localizedDescription)
        }
    }

    func disable() {
        guard isRequestedEnabled || isEnabled || isTransitioning || assertionID != 0 else { return }

        lastError = nil
        isRequestedEnabled = false
        expectedHelperStop = true
        writeStopSignal()

        if leaseDirectory != nil {
            isTransitioning = true
            statusMessage = "안전하게 해제하는 중…"
        } else {
            finishHelperStop(errorMessage: nil)
        }
    }

    func shutdown() {
        expectedHelperStop = true
        writeStopSignal()
        installerProcess?.terminate()
        installerProcess = nil
        installerErrorPipe = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        releasePowerAssertion()
        isEnabled = false
        isRequestedEnabled = false
        isTransitioning = false
        statusMessage = "꺼짐"
    }

    private func createPowerAssertion() throws {
        guard assertionID == 0 else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AgentAwake prevents system sleep" as CFString,
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

        let request = """
        owner_pid=\(ProcessInfo.processInfo.processIdentifier)
        owner_uid=\(uid)
        battery_floor=\(batteryFloor)
        max_seconds=\(maximumDurationHours * 60 * 60)

        """
        try Data(request.utf8).write(to: directory.appendingPathComponent("request"))
        try Data("starting\n".utf8).write(to: directory.appendingPathComponent("heartbeat"))
        try Data("state=requested\nreason=waiting\nactivated=0\n".utf8)
            .write(to: directory.appendingPathComponent("state"))
        return directory
    }

    private func helperIsReady() -> Bool {
        guard let status = try? String(contentsOf: helperStatusURL, encoding: .utf8),
              let values = try? helperStatusURL.resourceValues(
                  forKeys: [.contentModificationDateKey]
              ),
              let modifiedAt = values.contentModificationDate,
              Date().timeIntervalSince(modifiedAt) < 5 else {
            return false
        }
        let lines = status.split(separator: "\n")
        return lines.contains { $0 == "version=\(helperVersion)" }
            && lines.contains { $0 == "allowed_uid=\(getuid())" }
    }

    private func launchHelperInstaller() throws {
        guard let installerURL = Bundle.main.url(
            forResource: "agentawake-install-helper",
            withExtension: "sh"
        ), FileManager.default.isExecutableFile(atPath: installerURL.path) else {
            throw KeepAwakeError.helperResourcesMissing
        }

        let commandArguments = [
            "/bin/bash",
            installerURL.path,
            String(getuid()),
        ]
        let shellCommand = commandArguments.map(Self.shellQuote).joined(separator: " ")
        let appleScript = "do shell script \(Self.appleScriptQuote(shellCommand)) with administrator privileges"

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        installerProcess = process
        installerErrorPipe = errorPipe

        do {
            try process.run()
        } catch {
            installerProcess = nil
            installerErrorPipe = nil
            throw KeepAwakeError.helperInstallerLaunchFailed(error.localizedDescription)
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
        writeHeartbeat()

        if let installerProcess, !installerProcess.isRunning {
            let data = installerErrorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let rawMessage = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = rawMessage?.isEmpty == false ? rawMessage : nil
            let failed = installerProcess.terminationStatus != 0
            self.installerProcess = nil
            installerErrorPipe = nil

            if failed {
                finishEnableFailure(message ?? "전원 도우미 설치가 취소되었거나 실패했습니다.")
                return
            }
            activationStartedAt = Date()
            statusMessage = "전원 도우미 연결 중…"
        }

        guard let leaseDirectory else { return }
        let stateURL = leaseDirectory.appendingPathComponent("state")
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else {
            checkActivationTimeout()
            return
        }

        switch Self.field("state", in: state) {
        case "active":
            guard !expectedHelperStop else { return }
            isEnabled = true
            isRequestedEnabled = true
            isTransitioning = false
            activationStartedAt = nil
            statusMessage = "켜짐 · 덮개 닫힘 방지 중"
        case "stopped":
            finishHelperStop(errorMessage: Self.field("reason", in: state))
        case "error":
            finishHelperStop(errorMessage: Self.field("reason", in: state))
        default:
            checkActivationTimeout()
        }
    }

    private func checkActivationTimeout() {
        guard installerProcess == nil,
              let activationStartedAt,
              Date().timeIntervalSince(activationStartedAt) > 45 else {
            return
        }
        finishEnableFailure("전원 도우미가 제한 시간 안에 응답하지 않았습니다.")
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

    private func finishHelperStop(errorMessage: String?) {
        let wasEnabled = isEnabled || helperStateShowsActivation()

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        installerProcess = nil
        installerErrorPipe = nil
        releasePowerAssertion()
        isEnabled = false
        isRequestedEnabled = false
        isTransitioning = false

        if expectedHelperStop {
            statusMessage = "꺼짐"
        } else if wasEnabled {
            let reason = errorMessage ?? "안전장치가 잠자기 방지를 자동 해제했습니다."
            statusMessage = reason
            lastError = reason
        } else {
            statusMessage = "켜지지 않음"
            lastError = Self.activationFailureMessage(errorMessage)
        }

        activationStartedAt = nil
        expectedHelperStop = false
        cleanLeaseDirectory()
    }

    private func finishEnableFailure(_ message: String) {
        installerProcess?.terminate()
        installerProcess = nil
        installerErrorPipe = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        releasePowerAssertion()
        isEnabled = false
        isRequestedEnabled = false
        isTransitioning = false
        statusMessage = "켜지지 않음"
        lastError = Self.activationFailureMessage(message)
        activationStartedAt = nil
        expectedHelperStop = false
        cleanLeaseDirectory()
    }

    private func helperStateShowsActivation() -> Bool {
        guard let leaseDirectory else { return false }
        let stateURL = leaseDirectory.appendingPathComponent("state")
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return false
        }
        return Self.field("activated", in: state) == "1"
    }

    private func cleanLeaseDirectory() {
        if let leaseDirectory {
            try? FileManager.default.removeItem(at: leaseDirectory)
        }
        leaseDirectory = nil
    }

    private static func field(_ key: String, in contents: String) -> String? {
        let prefix = "\(key)="
        guard let line = contents.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(line.dropFirst(prefix.count))
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

    private static func activationFailureMessage(_ message: String?) -> String {
        if let message,
           message.localizedCaseInsensitiveContains("User canceled")
            || message.localizedCaseInsensitiveContains("-128") {
            return "관리자 승인이 취소되어 전원 도우미를 설치하지 못했습니다."
        }
        if let message, !message.isEmpty {
            return "잠자기 방지를 켜지 못했습니다: \(message)"
        }
        return "잠자기 방지를 켜지 못했습니다. 다시 시도해 주세요."
    }
}

private enum KeepAwakeError: LocalizedError {
    case powerAssertionFailed(code: IOReturn)
    case helperResourcesMissing
    case helperInstallerLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .powerAssertionFailed(let code):
            return "macOS 잠자기 방지 요청에 실패했습니다 (오류 \(code))."
        case .helperResourcesMissing:
            return "전원 도우미 설치 파일을 앱 번들에서 찾지 못했습니다."
        case .helperInstallerLaunchFailed(let message):
            return "전원 도우미 설치를 시작하지 못했습니다: \(message)"
        }
    }
}
