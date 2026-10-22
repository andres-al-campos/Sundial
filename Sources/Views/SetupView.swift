import SwiftUI

/// First-run onboarding shown until the BetterDisplay path + display name are
/// verified against real hardware. Presets stay locked behind this so a new user
/// on a different monitor doesn't drag sliders that silently do nothing.
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set up your monitor")
                        .font(.headline)
                    Text("Sundial controls your monitor's hardware brightness and contrast through BetterDisplay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. BetterDisplay path")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("/Applications/BetterDisplay.app/...", text: $appState.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: appState.cliPath) { _, _ in appState.save() }
                    Text("Install BetterDisplay if you haven't — the default path is usually correct.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Display name (partial match)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("e.g. GIGABYTE", text: $appState.displayName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: appState.displayName) { _, _ in appState.save() }
                    Text("Any part of the monitor name shown in BetterDisplay. Make sure DDC/CI is enabled in the monitor's on-screen menu.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    runTest()
                } label: {
                    HStack(spacing: 6) {
                        // Always laid out, shown only while testing, so the button
                        // keeps one size as the spinner comes and goes.
                        ProgressView().controlSize(.small).opacity(testing ? 1 : 0)
                        Text(testing ? "Connecting…" : "Connect Monitor")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .disabled(testing)
            }
            .padding(14)
            .measureContentHeight()
        }
        // Concrete, self-sizing height — a maxHeight-only frame collapses to 0 inside
        // MenuBarExtra(.window) on macOS 26. Matches SettingsView's cap; the copy is
        // kept tight enough to fit the Connect Monitor button, and the ScrollView is
        // a safety net for the longest error / unusually tall content.
        .scrollContentHeight("setup", cap: 420)
    }

    private func runTest() {
        testing = true
        error = nil
        Task {
            let result = await appState.validateSetup()
            testing = false
            error = result   // nil on success — isSetUp flips and the view swaps to presets
        }
    }
}
