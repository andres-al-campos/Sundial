import SwiftUI

/// First-run onboarding shown until the display name is found among the
/// connected monitors. Presets stay locked behind this so a new user
/// on a different monitor doesn't drag sliders that silently do nothing.
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        // A plain stack, not a measured ScrollView: its content is fixed and short,
        // so it sizes itself in one layout pass and the popup opens at its final
        // size. A ScrollView here started at 0 and jumped on the first open.
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up your monitor")
                    .font(.headline)
                Text("Sundial sets your monitor's own brightness and contrast over DDC.")
                    .font(.caption)
                    .foregroundStyle(Layout.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Monitor name (any part of it)")
                    .font(.caption.bold())
                    .foregroundStyle(Layout.dim)
                TextField("e.g. GIGABYTE", text: $appState.displayName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: appState.displayName) { _, _ in appState.save() }
                Text("Filled in from the connected monitor when there's one. Make sure DDC/CI is on in the monitor's on-screen menu.")
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
            .hoverShade()
        }
        .padding(14)
        .task {
            // Most people have one external monitor, so its name is the answer.
            guard appState.displayName.isEmpty, let first = await DDCController.monitors().first else { return }
            appState.displayName = first
        }
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
