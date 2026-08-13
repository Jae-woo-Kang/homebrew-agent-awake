import AgentAwakeCore
import AppKit
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
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "AgentAwake")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "AgentAwake"
            button.target = self
            button.action = #selector(toggleStatusPanel(_:))
        }
        self.statusItem = statusItem

        let rootView = AgentAwakeMenu(model: model)
            .frame(width: 370, height: 500, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }

        let hostingController = NSHostingController(rootView: rootView)
        let panel = PersistentStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 500),
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
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                    Text("Mac 잠자기 방지")
                        .font(.headline)
                }
                .toggleStyle(.switch)

                Label(model.keepAwakeMessage, systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("관리자 승인 없이 즉시 적용됩니다. 화면은 꺼질 수 있지만 시스템과 네트워크는 계속 작동합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle(
                    isOn: Binding(
                        get: { model.closedLidEnabled || model.closedLidTransitioning },
                        set: { model.setClosedLid($0) }
                    )
                ) {
                    HStack(spacing: 8) {
                        Text("덮개를 닫아도 유지")
                        if model.closedLidTransitioning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(!model.keepAwakeEnabled)

                Label(model.closedLidMessage, systemImage: "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("선택 기능입니다. 켜면 관리자 승인 창이 열리지만 AgentAwake 창과 메뉴바 아이콘은 유지됩니다.")
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
