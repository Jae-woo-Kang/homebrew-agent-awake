import AgentAwakeCore
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = AgentSnapshot()
    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var keepAwakeTransitioning = false
    @Published private(set) var keepAwakeMessage = "꺼짐"
    @Published private(set) var errorMessage: String?

    let statusMonitor: AgentStatusMonitor
    let keepAwakeController: KeepAwakeController

    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.statusMonitor = AgentStatusMonitor()
        self.keepAwakeController = KeepAwakeController()
        bind()
    }

    init(statusMonitor: AgentStatusMonitor, keepAwakeController: KeepAwakeController) {
        self.statusMonitor = statusMonitor
        self.keepAwakeController = keepAwakeController
        bind()
    }

    private func bind() {
        statusMonitor.$snapshot
            .sink { [weak self] in self?.snapshot = $0 }
            .store(in: &cancellables)

        keepAwakeController.$isRequestedEnabled
            .sink { [weak self] in self?.keepAwakeEnabled = $0 }
            .store(in: &cancellables)

        keepAwakeController.$isTransitioning
            .sink { [weak self] in self?.keepAwakeTransitioning = $0 }
            .store(in: &cancellables)

        keepAwakeController.$statusMessage
            .sink { [weak self] in self?.keepAwakeMessage = $0 }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            statusMonitor.$lastError,
            keepAwakeController.$lastError
        )
        .map { monitorError, keepAwakeError in keepAwakeError ?? monitorError }
        .sink { [weak self] in self?.errorMessage = $0 }
        .store(in: &cancellables)
    }

    func setKeepAwake(_ enabled: Bool) {
        keepAwakeController.setEnabled(enabled)
    }

    func refresh() {
        statusMonitor.refresh()
    }
}
