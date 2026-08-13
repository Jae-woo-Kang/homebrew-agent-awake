import AgentAwakeCore
import AppKit
import Combine
import SwiftUI

@main
enum AgentAwakeApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AgentAwakeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AgentAwakeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusPanel: PersistentStatusPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleStatusPanel(_:))
        }
        self.statusItem = statusItem

        Publishers.CombineLatest(model.$keepAwakeEnabled, model.$keepAwakeTransitioning)
            .sink { [weak self] enabled, transitioning in
                self?.updateStatusItemIcon(enabled: enabled, transitioning: transitioning)
            }
            .store(in: &cancellables)

        let rootView = AgentAwakeMenu(model: model)
            .frame(width: 370, height: 430, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }

        let hostingController = NSHostingController(rootView: rootView)
        let panel = PersistentStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 430),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.statusPanel = panel

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.closePanelForLocalClickIfNeeded(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePanelIfAllowed()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        model?.keepAwakeController.shutdown()
    }

    @objc private func toggleStatusPanel(_ sender: NSStatusBarButton) {
        guard let panel = statusPanel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        position(panel: panel, below: sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanelForLocalClickIfNeeded(_ event: NSEvent) {
        guard event.window !== statusPanel,
              event.window !== statusItem?.button?.window else {
            return
        }
        closePanelIfAllowed()
    }

    private func updateStatusItemIcon(enabled: Bool, transitioning: Bool) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        let description: String
        if transitioning {
            symbolName = "ellipsis.circle"
            description = "AgentAwake 전환 중"
        } else if enabled {
            symbolName = "eye.fill"
            description = "AgentAwake 잠자기 방지 켜짐"
        } else {
            symbolName = "eye"
            description = "AgentAwake 잠자기 방지 꺼짐"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    private func closePanelIfAllowed() {
        guard model?.keepAwakeTransitioning != true else { return }
        statusPanel?.orderOut(nil)
    }

    private func position(panel: NSPanel, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let panelFrame = panel.frame
        let idealX = buttonFrame.midX - (panelFrame.width / 2)
        let minimumX = screenFrame.minX + 8
        let maximumX = screenFrame.maxX - panelFrame.width - 8
        let x = min(max(idealX, minimumX), maximumX)
        let y = buttonFrame.minY - panelFrame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class PersistentStatusPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct AgentAwakeMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            AgentRow(name: "Codex", presence: model.snapshot.codex)
            AgentRow(name: "Claude Code", presence: model.snapshot.claude)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    isOn: Binding(
                        get: { model.keepAwakeEnabled },
                        set: { model.setKeepAwake($0) }
                    )
                ) {
                    HStack(spacing: 8) {
                        Text("Mac 잠자기 방지")
                            .font(.headline)
                        if model.keepAwakeTransitioning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(model.keepAwakeTransitioning)

                Label(model.keepAwakeMessage, systemImage: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("켜면 덮개를 닫아도 시스템과 네트워크가 계속 작동합니다. 전원 도우미 설치 시 최초 한 번만 관리자 승인이 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("안전을 위해 배터리 20% 이하, 심각한 발열 또는 12시간 경과 시 자동으로 해제됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("새로고침") {
                    model.refresh()
                }
                Spacer()
                Button("AgentAwake 종료") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 370, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AgentAwake")
                    .font(.title3.weight(.semibold))
                Text("코딩 에이전트 상태와 Mac 절전 제어")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.snapshot.hasRunningAgent ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
                .accessibilityLabel(model.snapshot.hasRunningAgent ? "에이전트 실행 중" : "에이전트 미실행")
        }
    }
}

private struct AgentRow: View {
    let name: String
    let presence: AgentPresence

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(presence.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(name)
                        .font(.headline)
                    Spacer()
                    Text(presence.isRunning ? "실행 중" : "미실행")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(presence.isRunning ? Color.green : Color.secondary)
                }

                HStack(spacing: 6) {
                    SurfaceBadge(title: "CLI", active: presence.cli)
                    SurfaceBadge(title: "VS Code", active: presence.vscode)
                    SurfaceBadge(title: "App", active: presence.app)
                }
            }
        }
    }
}

private struct SurfaceBadge: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(title)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(active ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .foregroundStyle(active ? Color.primary : Color.secondary)
    }
}
