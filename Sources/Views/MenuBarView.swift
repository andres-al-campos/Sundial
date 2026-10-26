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

                if !showSettings, appState.isSetUp, let caption = headerCaption {
                    Text(caption)
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
                modePicker
                Divider()
                if appState.mode == .auto {
                    AutoView()
                } else {
                    PresetListView(expandedPresetID: $expandedPresetID, appState: appState)
                }
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
        // The panel keeps this view (and its @State) across opens, so the init
        // value only counts once, and onDisappear doesn't fire on every close.
        // Resigning key is the close signal that always arrives: reset the
        // expanded card there, so the next open shows the active preset.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            expandedPresetID = appState.activePresetID
        }
        // The schedule can move on while the popup is closed.
        .onChange(of: appState.activePresetID) { _, newValue in
            if NSApp.keyWindow == nil { expandedPresetID = newValue }
        }
    }
}

extension MenuBarView {
    /// The preset in force in Schedule mode. Auto needs none: its tab says it.
    private var headerCaption: String? {
        if appState.mode == .auto { return nil }
        return appState.preset(for: appState.activePresetID)?.name
    }

    /// Auto or Schedule: one or the other drives the monitor, so a segmented
    /// control (pick one), not tabs (look at one) or a switch (one thing on or
    /// off). Its halves are equal and span the popup.
    private var modePicker: some View {
        ModeSegments(mode: appState.mode, onPick: setMode)
            .frame(height: 22)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    private func setMode(_ newMode: AppState.Mode) {
        guard newMode != appState.mode else { return }
        appState.previewingPresetID = nil
        appState.mode = newMode
        appState.save()
        // Whichever mode is now on takes the monitor at once, in full.
        if newMode == .auto { appState.onPreviewEnded?() } else { appState.onScheduleChanged?() }
        expandedPresetID = appState.activePresetID
    }
}

// MARK: - Mode Segments

/// The Mac's segmented control with equal segments filling its width. SwiftUI's
/// segmented Picker sizes to its labels, which left the right side empty.
private struct ModeSegments: NSViewRepresentable {
    let mode: AppState.Mode
    let onPick: (AppState.Mode) -> Void

    private static let modes: [AppState.Mode] = [.auto, .schedule]

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Auto", "Schedule"], trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.picked(_:)))
        control.segmentDistribution = .fillEqually
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onPick = onPick
        control.selectedSegment = Self.modes.firstIndex(of: mode) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject {
        var onPick: (AppState.Mode) -> Void
        init(onPick: @escaping (AppState.Mode) -> Void) { self.onPick = onPick }

        @objc func picked(_ sender: NSSegmentedControl) {
            onPick(ModeSegments.modes[sender.selectedSegment])
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
