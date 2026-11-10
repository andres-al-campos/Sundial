import SwiftUI

/// The desktop window: what you sit down to change. An AppKit window rather than
/// a SwiftUI `Window` scene, which opens by itself at launch and would greet
/// every login with it. The Dock icon shows only while it's open, since Sundial
/// otherwise lives in the menu bar.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static var closing: NSObjectProtocol?
    /// Below this the bands are too short for their hour labels.
    static let minSize = NSSize(width: 760, height: 420)

    static func show(_ state: AppState) {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Sundial"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MainWindowView()
                .frame(minWidth: minSize.width, minHeight: minSize.height)
                .environmentObject(state))
            w.center()
            w.setFrameAutosaveName("SundialMain")
            closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
            }
            window = w
            RedoKeys.install(for: w)
        }
        window?.makeKeyAndOrderFront(nil)
        // With keyboard navigation on, AppKit otherwise focuses the first button and
        // its ring reads as that button being on. Tab still gets there.
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension WindowSection {
    var title: String {
        switch self {
        case .lights: return "Lights"
        case .presets: return "Presets"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .lights: return "lightbulb"
        case .presets: return "display"
        case .settings: return "gearshape"
        }
    }
}

private struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(WindowSection.allCases, selection: Binding(get: { appState.windowSection }, set: { if let s = $0 { appState.windowSection = s } })) { s in
                Label(s.title, systemImage: s.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            switch appState.windowSection {
            case .lights: LightsView()
            case .presets: PresetsSection()
            case .settings:
                ScrollView {
                    SettingsView()
                        .frame(maxWidth: 520 + 2 * Layout.edge, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// The Schedule's presets, with room to edit them.
private struct PresetsSection: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undo
    /// Settings' width, from the same left edge, so switching pages moves nothing: across the
    /// whole window the sliders ran long and the values sat far from their labels.
    private static let column = 520 + 2 * Layout.edge
    @State private var expanded: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // At the column's top right, beside the cards it adds to.
            HStack {
                Spacer()
                // The popup's button, so a button looks the same wherever it is.
                Button(action: addPreset) {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Add Preset") }
                }
                .buttonStyle(.outlined(OutlinedButtonStyle.createBlue))
                .font(.subheadline)
            }
            .frame(height: 28)
            .padding(.horizontal, Layout.edge)
            .padding(.vertical, 10)
            .frame(maxWidth: Self.column)
            .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                // The cards span what Settings' content spans, their lines on its lines.
                PresetListView(expandedPresetID: $expanded, appState: appState, height: geo.size.height,
                               width: Self.column, inset: Layout.edge)
            }
        }
        // The popup's preset card opens the window on that preset.
        .onAppear(perform: openAsked)
        .onChange(of: appState.presetToOpen) { _, _ in openAsked() }
        .onDisappear {
            // Leaving the list ends any preview, so the monitor goes back to the
            // scheduled preset.
            if appState.previewingPresetID != nil {
                appState.previewingPresetID = nil
                appState.onPreviewEnded?()
            }
        }
    }

    private func openAsked() {
        guard let id = appState.presetToOpen else { return }
        appState.presetToOpen = nil
        expanded = id
    }

    /// A new preset at noon, opened for editing; the list scrolls to it.
    private func addPreset() {
        let preset = Preset(name: "New Preset", hardwareBrightness: 70, hardwareContrast: 75, nightShift: 0)
        PresetsHistory.change(preset.id, "Add Preset", in: appState, undo: undo) {
            appState.addPreset(preset)
            appState.addScheduleEntry(ScheduleEntry(presetID: preset.id, hour: 12, minute: 0))
        }
        appState.onScheduleChanged?()
        expanded = preset.id
    }
}
