import AgentAwakeCore
import AppKit
import Foundation

@MainActor
final class AgentStatusMonitor: ObservableObject {
    @Published private(set) var snapshot = AgentSnapshot()
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private var isRefreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
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

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.readProcesses()
            let capturedAt = Date()

            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false

                switch result {
                case .success(let processes):
                    self.snapshot = AgentProcessClassifier.classify(
                        processes: processes,
                        runningApplications: apps,
                        capturedAt: capturedAt
                    )
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
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
