import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 260)
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
