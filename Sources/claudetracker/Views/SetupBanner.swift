import SwiftUI
import AppKit

/// Prompts the user to install (or finish) the statusline bridge. Hidden when
/// the bridge is already installed and live data is flowing.
struct SetupBanner: View {
    @ObservedObject var installer = StatuslineInstaller.shared
    @EnvironmentObject private var bridge: StatuslineBridge
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if shouldShow {
            bannerBody
        }
    }

    private var shouldShow: Bool {
        switch installer.status {
        case .installed:
            // Even if installed, the bridge file might not have been written yet
            // (next Claude Code statusline tick writes it). Hide as soon as the
            // app sees a fresh bridge payload.
            return !bridge.isFresh
        case .notConfigured, .externalStatuslineFound:
            return true
        }
    }

    @ViewBuilder
    private var bannerBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold))
                Spacer()
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                primaryButton
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        .padding(.bottom, 10)
    }

    private var title: String {
        switch installer.status {
        case .installed:               return "Waiting for first statusline tick"
        case .notConfigured:           return "Statusline hook not installed"
        case .externalStatuslineFound: return "Existing statusline detected"
        }
    }

    private var icon: String {
        switch installer.status {
        case .installed:               return "hourglass"
        case .notConfigured:           return "exclamationmark.triangle.fill"
        case .externalStatuslineFound: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch installer.status {
        case .installed: return .secondary
        default:         return .orange
        }
    }

    private var message: String {
        switch installer.status {
        case .installed:
            return "The bridge is set up, but no Claude Code statusline tick has been observed yet. Rate-limit data will appear on the next tick."
        case .notConfigured:
            return "Claude Tracker needs to hook into Claude Code's statusline to read rate-limit data. One click installs it."
        case .externalStatuslineFound(let command, _):
            return "A different statusline is already configured: \(command). Use Settings → Setup to install manually."
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch installer.status {
        case .installed:
            EmptyView()
        case .notConfigured:
            Button("Install hook") {
                do { try installer.install() } catch { /* error surfaced in Settings */ }
            }
            .font(.caption)
        case .externalStatuslineFound:
            Button("Copy bridge snippet") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(StatuslineInstaller.bridgeScript, forType: .string)
            }
            .font(.caption)
        }
    }
}
