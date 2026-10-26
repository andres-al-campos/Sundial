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

            // The mode control sits in the header block, so no line between them.
            if !appState.isSetUp || showSettings { Divider() }

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
    /// off). Its halves are equal and span the popup, and it belongs to the
    /// header, so there's no line between them.
    private var modePicker: some View {
        ModeSegments(mode: appState.mode, onPick: setMode)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
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

/// A segmented control drawn in SwiftUI so it can move: the selected pill
/// slides to the mode picked instead of jumping, and the other half glows
/// faintly under the pointer. Halves are equal and fill the width.
private struct ModeSegments: View {
    let mode: AppState.Mode
    let onPick: (AppState.Mode) -> Void
    @Namespace private var pill
    @State private var hovered: AppState.Mode?

    private static let modes: [(AppState.Mode, String)] = [(.auto, "Auto"), (.schedule, "Schedule")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.modes, id: \.0) { item, label in
                let on = item == mode
                Text(label)
                    .font(.system(size: 11, weight: on ? .medium : .regular))
                    .foregroundStyle(on ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .controlColor))
                                .shadow(color: .black.opacity(0.18), radius: 0.75, y: 0.5)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        } else if hovered == item {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.12)) { hovered = inside ? item : (hovered == item ? nil : hovered) }
                    }
                    .onTapGesture {
                        guard !on else { return }
                        onPick(item)
                    }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
        // Only the pill animates; the panel below swaps in its own transaction.
        .animation(.easeOut(duration: 0.22), value: mode)
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
