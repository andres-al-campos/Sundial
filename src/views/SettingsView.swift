import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Monitor
            VStack(alignment: .leading, spacing: 6) {
                Text("Monitor")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Display name (partial match)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("GIGABYTE", text: $appState.displayName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.displayName) { _, _ in appState.save() }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("BetterDisplay path")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("/Applications/BetterDisplay.app/...", text: $appState.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: appState.cliPath) { _, _ in appState.save() }
                }
            }

            Divider()

            // Lamps
            VStack(alignment: .leading, spacing: 6) {
                Text("Lamps")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack {
                    Text(appState.hueHost == nil ? "Not paired with a Hue Bridge" : "Paired with your Hue Bridge")
                    Spacer()
                    Button(appState.hueHost == nil ? "Pair Hue Bridge" : "Pair again") { appState.onPairLamps?() }
                        .controlSize(.small)
                        .hoverShade()
                }
                // Two lines held whatever the status says, so a status change
                // doesn't move what's below it.
                Label {
                    Text(appState.lampStatus)
                        .lineLimit(2, reservesSpace: true)
                } icon: {
                    Image(systemName: appState.lampStatus.hasPrefix("Paired") ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(appState.lampStatus.hasPrefix("Paired") ? .green : .secondary)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Divider()

            LocationSection()

            Divider()

            // Behavior
            VStack(alignment: .leading, spacing: 8) {
                Text("Behavior")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                    .controlSize(.small)
                    .onChange(of: appState.launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                // Only let a Release build (installed to /Applications via
                                // build.sh) claim the login item. A Debug build runs from an
                                // ephemeral DerivedData path; registering it there means a
                                // later Clean Build / Xcode prune leaves macOS launching a
                                // stale or missing binary on the next reboot.
                                #if DEBUG
                                print("[Sundial] Debug build — skipping login-item registration so it can't bind a DerivedData path. Install via ./build.sh to enable launch-at-login from /Applications.")
                                #else
                                try SMAppService.mainApp.register()
                                #endif
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("[Sundial] Login item error: \(error.localizedDescription). Open System Settings → General → Login Items to resolve.")
                        }
                        appState.save()
                    }

                Toggle("Re-apply preset after sleep/wake", isOn: $appState.applyOnWake)
                    .controlSize(.small)
                    .onChange(of: appState.applyOnWake) { _, _ in appState.save() }
            }
        }
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, 14)
    }
}
