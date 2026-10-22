import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var expandedPresetID: UUID?

    /// `activePresetID` is the card to open expanded. Taking it at construction,
    /// instead of expanding in onAppear, keeps the popup from opening collapsed
    /// and then growing.
    init(activePresetID: UUID?) {
        _expandedPresetID = State(initialValue: activePresetID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Sundial")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()

                if let preset = appState.preset(for: appState.activePresetID), !showSettings, appState.isSetUp {
                    Text(preset.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // The gear only appears once setup is complete — before that the
                // SetupView already exposes the path/name fields, so a Settings
                // toggle would be redundant (and could strand the user on an empty
                // settings panel with no way back to onboarding).
                if appState.isSetUp {
                    HeaderButton(
                        icon: showSettings ? "arrow.left" : "gear",
                        help: showSettings ? "Back to presets" : "Settings"
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showSettings.toggle()
                            expandedPresetID = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if !appState.isSetUp {
                SetupView()
            } else if showSettings {
                SettingsView()
            } else {
                PresetListView(expandedPresetID: $expandedPresetID, appState: appState)
            }

            Divider()

            HoverButton("Quit Sundial") {
                NSApplication.shared.terminate(nil)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .onDisappear {
            // Popover closed — always end any active preview so the monitor
            // snaps back to the scheduled preset.
            if appState.previewingPresetID != nil {
                appState.previewingPresetID = nil
                appState.onPreviewEnded?()
            }
            expandedPresetID = appState.activePresetID
        }
    }
}

// MARK: - Header Button

struct HeaderButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - Hover Button

struct HoverButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
    }
}
