import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // A plain stack, not a measured ScrollView: its content is fixed and short,
        // so it sizes itself in one layout pass and the popup opens at its final
        // size. A ScrollView here started at 0 and jumped on the first open.
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
        .padding(14)
    }
}
