import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            SetupTab()
                .tabItem { Label("Setup", systemImage: "link") }
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            PricingTab()
                .tabItem { Label("Pricing", systemImage: "dollarsign.circle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct SetupTab: View {
    @ObservedObject private var installer = StatuslineInstaller.shared
    @State private var actionError: String?

    var body: some View {
        Form {
            Section("Statusline hook") {
                statusLine
                actionButtons
                if let err = actionError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Text("Claude Tracker reads rate-limit data from files that Claude Code's statusline script writes. Installing the hook sets up a small script at ~/.claude/statusline-claudetracker.sh and points statusLine in ~/.claude/settings.json at it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { installer.refresh() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch installer.status {
        case .installed(let path):
            Label("Installed at \(path)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption.monospacedDigit())
        case .notConfigured:
            Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .externalStatuslineFound(let command, _):
            VStack(alignment: .leading, spacing: 4) {
                Label("A different statusline is configured", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(command)
                    .font(.caption.monospacedDigit())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch installer.status {
        case .installed:
            Button("Uninstall hook") {
                do { try installer.uninstall() ; actionError = nil }
                catch { actionError = error.localizedDescription }
            }
        case .notConfigured:
            Button("Install hook") {
                do { try installer.install() ; actionError = nil }
                catch { actionError = error.localizedDescription }
            }
            .keyboardShortcut(.defaultAction)
        case .externalStatuslineFound:
            HStack {
                Button("Copy bridge snippet") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(StatuslineInstaller.bridgeScript, forType: .string)
                }
                Text("Paste into your existing statusline script, right after `input=$(cat)`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationsTab: View {
    @ObservedObject private var notifier = NotificationService.shared

    @AppStorage(SettingsKey.notify5h80) private var notify5h80: Bool = true
    @AppStorage(SettingsKey.notify5h95) private var notify5h95: Bool = true
    @AppStorage(SettingsKey.notify7d80) private var notify7d80: Bool = true
    @AppStorage(SettingsKey.notify7d95) private var notify7d95: Bool = true

    var body: some View {
        Form {
            Section("5-hour block") {
                Toggle("Notify at 80%", isOn: $notify5h80)
                Toggle("Notify at 95%", isOn: $notify5h95)
            }
            Section("7-day window") {
                Toggle("Notify at 80%", isOn: $notify7d80)
                Toggle("Notify at 95%", isOn: $notify7d95)
            }
            Section {
                authRow
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .task { await notifier.refreshAuthorization() }
    }

    @ViewBuilder
    private var authRow: some View {
        switch notifier.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Notifications permission granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .denied:
            VStack(alignment: .leading, spacing: 4) {
                Label("Notifications disabled in System Settings", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
            }
        case .notDetermined:
            Button("Request permission") {
                Task { await notifier.requestPermissionIfNeeded() }
            }
            .font(.caption)
        @unknown default:
            EmptyView()
        }
    }
}

private struct GeneralTab: View {
    @AppStorage(SettingsKey.menuBarFormat) private var menuBarFormatRaw: String = MenuBarFormat.fiveHour.rawValue
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Picker("Menubar text", selection: $menuBarFormatRaw) {
                ForEach(MenuBarFormat.allCases) { f in
                    Text(f.label).tag(f.rawValue)
                }
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    if !LaunchAtLogin.set(newValue) {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct PricingTab: View {
    @ObservedObject private var pricing = PricingService.shared
    @AppStorage(SettingsKey.pricingRefreshInterval) private var intervalRaw: Int = PricingRefreshInterval.daily.rawValue

    var body: some View {
        Form {
            Picker("Auto-refresh pricing", selection: $intervalRaw) {
                ForEach(PricingRefreshInterval.allCases) { i in
                    Text(i.label).tag(i.rawValue)
                }
            }
            HStack {
                Button {
                    Task { await pricing.refresh() }
                } label: {
                    if pricing.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh now")
                    }
                }
                .disabled(pricing.isRefreshing)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let t = pricing.lastUpdated {
                        Text("Last updated \(Fmt.relative(from: t))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(pricing.modelCount) model\(pricing.modelCount == 1 ? "" : "s") cached")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No prices fetched yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let err = pricing.lastErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            Text("Prices are fetched from LiteLLM's model_prices_and_context_window.json. If fetching fails, claudetracker falls back to the on-disk cache, then to a small hardcoded table.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct AboutTab: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Claude Tracker")
                .font(.title2.weight(.semibold))
            Text(version)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("A menubar view of Claude Code usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
