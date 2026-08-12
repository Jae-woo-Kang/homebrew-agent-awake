import AgentAwakeCore
import AppKit
import SwiftUI

@main
struct AgentAwakeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            AgentAwakeMenu(model: model)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel(menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if model.keepAwakeEnabled || model.keepAwakeTransitioning {
            return "bolt.shield.fill"
        }
        return model.snapshot.hasRunningAgent ? "terminal.fill" : "moon.zzz"
    }

    private var menuBarAccessibilityLabel: String {
        model.keepAwakeEnabled ? "AgentAwake 잠자기 방지 켜짐" : "AgentAwake"
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
                        get: { model.toggleValue },
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

                Label(model.keepAwakeMessage, systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("화면은 꺼질 수 있지만 시스템과 네트워크는 계속 작동합니다. 덮개 닫힘 지원은 관리자 승인이 필요합니다.")
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
        .frame(width: 350)
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
