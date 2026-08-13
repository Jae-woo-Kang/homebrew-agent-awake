import AppKit
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "꺼짐"
    @Published private(set) var lastError: String?

    private var assertionID: IOPMAssertionID = 0

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
    }

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
            statusMessage = "켜짐 · 자동 잠자기 방지 중"
        } catch {
            isEnabled = false
            statusMessage = "켜지지 않음"
            lastError = error.localizedDescription
        }
    }

    func disable() {
        guard isEnabled || assertionID != 0 else { return }

        lastError = nil
        releasePowerAssertion()
        isEnabled = false
        statusMessage = "꺼짐"
    }

    func shutdown() {
        releasePowerAssertion()
        isEnabled = false
        statusMessage = "꺼짐"
    }

    private func createPowerAssertion() throws {
        guard assertionID == 0 else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AgentAwake prevents automatic idle system sleep" as CFString,
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

    @objc private func applicationWillTerminate() {
        shutdown()
    }
}

private enum KeepAwakeError: LocalizedError {
    case powerAssertionFailed(code: IOReturn)

    var errorDescription: String? {
        switch self {
        case .powerAssertionFailed(let code):
            return "macOS 잠자기 방지 요청에 실패했습니다 (오류 \(code))."
        }
    }
}
