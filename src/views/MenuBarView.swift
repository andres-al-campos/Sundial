import SwiftUI

/// For seeing what Sundial is doing and tweaking it. Everything you sit down
/// to change lives in the desktop window.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Sundial")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if !appState.isSetUp {
                Divider()
                SetupView()
            } else {
                modePicker
                Divider()
                if appState.mode == .auto {
                    AutoView()
                } else {
                    CurrentPresetCard()
                }
            }

            Divider()

            HStack {
                HoverButton("Quit Sundial") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
                if appState.isSetUp {
                    HoverButton("Open Sundial", rest: HoverButton.createBlue) {
                        // The popup is the key window here. Nothing closes it for us,
                        // because the new window comes up without it losing focus first.
                        NSApp.keyWindow?.close()
                        appState.onOpenWindow?()
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .onDisappear {
            // Popup closed: end any preview, so the monitor goes back to the
            // scheduled preset.
            if appState.previewingPresetID != nil {
                appState.previewingPresetID = nil
                appState.onPreviewEnded?()
            }
        }
    }
}

extension MenuBarView {
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
        // The popup resizes to the other mode's panel, eased, not in one jump.
        withAnimation(.easeInOut(duration: 0.15)) { appState.setMode(newMode) }
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

/// A footer action: dimmed text that turns primary under the pointer.
struct HoverButton: View {
    let label: String
    let systemImage: String?
    /// The colour at rest: secondary, or blue for an action that creates
    /// something. The link blue, not the accent: the accent is too dark to
    /// read on the popup's glass.
    let rest: Color
    let action: () -> Void
    @State private var isHovered = false

    static let createBlue = Color(nsColor: .linkColor)

    init(_ label: String, systemImage: String? = nil, rest: Color = .secondary, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.rest = rest
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let systemImage {
                // Not a Label: its gap between icon and text is wide enough to
                // read as two things in a footer.
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                    Text(label)
                }
            } else {
                Text(label)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? Color.primary : rest)
        .onHover { isHovered = $0 }
    }
}

/// Every button in a window answers the pointer the same way. macOS leaves its standard
/// buttons still until they're pressed, so a button can't be told from a label by aiming at it.
private struct HoverShade: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(hovered ? 0.12 : 0))
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

extension View {
    func hoverShade() -> some View { modifier(HoverShade()) }
}
