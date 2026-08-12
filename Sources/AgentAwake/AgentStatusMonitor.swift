import AgentAwakeCore
import AppKit
import Foundation

@MainActor
final class AgentStatusMonitor: NSObject, ObservableObject {
    @Published private(set) var snapshot = AgentSnapshot()
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var isRefreshing = false

    override init() {
        super.init()
        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let apps = NSWorkspace.shared.runningApplications.map {
            RunningApplicationInfo(
                localizedName: $0.localizedName ?? "",
                bundleIdentifier: $0.bundleIdentifier ?? "",
                bundlePath: $0.bundleURL?.path ?? ""
            )
        }

        let result = Self.readProcesses()
        let capturedAt = Date()
        isRefreshing = false

        switch result {
        case .success(let processes):
            snapshot = AgentProcessClassifier.classify(
                processes: processes,
                runningApplications: apps,
                capturedAt: capturedAt
            )
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    @objc private func refreshTimerFired() {
        refresh()
    }

    private static func readProcesses() -> Result<[ProcessRecord], Error> {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "ps failed"
                throw ProcessReadError(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let output = String(data: data, encoding: .utf8) ?? ""
            return .success(ProcessListParser.parse(output))
        } catch {
            return .failure(error)
        }
    }
}

private struct ProcessReadError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message.isEmpty ? "Unable to inspect running processes." : message
    }
}
