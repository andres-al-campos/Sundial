import SwiftUI

/// For seeing what Sundial is doing and tweaking it. Everything you sit down
/// to change lives in the desktop window.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Sundial")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Segments(items: [(.display, "Display"), (.lighting, lightsLabel)], picked: appState.popupTab,
                     orange: appState.lampsOffTheDay ? .lighting : nil, onPick: setTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            Divider()
            if appState.popupTab == .lighting {
                LightingPanel()
            } else if !appState.isSetUp {
                SetupView()
            } else {
                screenRow
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
    /// What drives the monitor, as a popup that names both: a switch named only one side, and a
    /// segmented row under Display | Lights read as a second level of tabs.
    private var screenRow: some View {
        HStack(spacing: 8) {
            // The label carries the verb, so it reads "Follows room light": "Screen" under the
            // Display tab said the same thing twice.
            Text("Follows")
                .font(.caption)
            Spacer(minLength: 0)
            PopUp(items: Self.modeNames, selected: appState.mode == .auto ? 0 : 1) { i in
                // The popup resizes to the other mode's panel, eased, not in one jump.
                withAnimation(.easeInOut(duration: 0.15)) { appState.setMode(i == 0 ? .auto : .schedule) }
            }
            .controlSize(.small)
            .frame(width: Self.modeWidth)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private static let modeNames = ["Room light", "Schedule"]
    /// The longer name and the arrows, so the button is the same width in either mode.
    private static let modeWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        return ceil(modeNames.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 120) + 40
    }()

    /// The window's name for them, and singular for someone with one bulb.
    private var lightsLabel: String { appState.lights?.count == 1 ? "Light" : "Lights" }

    private func setTab(_ tab: AppState.PopupTab) {
        withAnimation(.easeInOut(duration: 0.15)) { appState.popupTab = tab }
    }
}

// MARK: - Segments

/// A segmented control drawn in SwiftUI so it can move: the selected pill slides to the one
/// picked instead of jumping, and the others glow faintly under the pointer. Equal parts that
/// fill the width.
struct Segments<Value: Hashable>: View {
    let items: [(Value, String)]
    let picked: Value
    /// The one whose label is orange: the lights are off the day, as the menu bar's sun says, and
    /// this is the way to them.
    var orange: Value? = nil
    let onPick: (Value) -> Void
    @Namespace private var pill
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item, label in
                let on = item == picked
                Text(label)
                    .font(.system(size: 11, weight: on ? .medium : .regular))
                    .foregroundStyle(item == orange ? AnyShapeStyle(.orange) : on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
        .animation(.easeOut(duration: 0.22), value: picked)
        .animation(.easeOut(duration: 0.15), value: orange)
    }
}

// MARK: - Outlined button

/// A button inside a popup panel: an outline, so it reads as something to press among the
/// panel's labels, which plain text didn't. The footer's links stay plain.
struct OutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Outlined(configuration: configuration)
    }

    private struct Outlined: View {
        let configuration: Configuration
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(.primary.opacity(configuration.isPressed ? 0.14 : hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.2)) }
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.1), value: hovered)
        }
    }
}

extension ButtonStyle where Self == OutlinedButtonStyle {
    static var outlined: OutlinedButtonStyle { .init() }
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
