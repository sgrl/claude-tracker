import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PricingTab()
                .tabItem { Label("Pricing", systemImage: "dollarsign.circle") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 320)
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
