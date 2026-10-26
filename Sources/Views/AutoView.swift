import SwiftUI

/// Auto mode's panel: how bright the room is, the one brightness to touch day
/// to day, and the two ends the room picks between.
struct AutoView: View {
    @EnvironmentObject var appState: AppState
    @State private var expandedEnd: AppState.EndKind?

    var body: some View {
        VStack(spacing: 0) {
            now
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            EndCard(kind: .dark, title: "Dark room", expanded: $expandedEnd)
            Divider()
            EndCard(kind: .bright, title: "Bright room", expanded: $expandedEnd)
            Divider()
            warmth
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        // Closing the popup collapses the cards, and with them any end preview.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            expandedEnd = nil
        }
    }

    // MARK: Now

    /// Three rows of fixed height whatever the state, so a hold starting or
    /// lapsing, or the sensor dropping out, never resizes the popup.
    @ViewBuilder
    private var now: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lux = appState.roomLux {
                HStack(spacing: 8) {
                    Text("Room")
                        .font(.caption)
                        .frame(width: 72, alignment: .leading)
                    RoomMeter(position: RoomLight.position(lux: lux))
                    Text("\(Int(lux.rounded())) lux")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
                .frame(height: 20)
                HeldBrightnessSlider()
                    .frame(height: 20)
                holdRow
                    .frame(height: 22)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reading from the light sensor")
                        .font(.caption.weight(.medium))
                    Text("The lid may be closed, or the sensor covered. Following the schedule until it's back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: 20 + 10 + 20 + 10 + 22, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var holdRow: some View {
        HStack(spacing: 8) {
            if let hold = appState.hold {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Held · back to the room \(hold.expires, style: .relative)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Button("Back to Auto") { appState.onHold?(nil) }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            } else {
                Text("Following the room")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: Warmth

    private var warmth: some View {
        HStack(spacing: 8) {
            Text("Night Shift")
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Text("\(scheduledNightShift)% now, from your schedule")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var scheduledNightShift: Int {
        Scheduler.activeEntry(in: appState.schedule, presets: appState.presets, at: Date())
            .flatMap { appState.preset(for: $0.presetID) }?.nightShift ?? 0
    }
}

// MARK: - Room meter

/// Where the room sits between dark and bright. Read-only: the room sets it.
private struct RoomMeter: View {
    let position: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(red: 0.96, green: 0.77, blue: 0.32)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, min(geo.size.width - 2, geo.size.width * position - 1)))
                    .animation(.easeInOut(duration: 0.8), value: position)
            }
            .frame(height: geo.size.height)
        }
    }
}

// MARK: - Brightness

/// The one control to touch day to day. Dragging moves the monitor at once and
/// holds there; between drags it shows what Auto has the monitor at.
private struct HeldBrightnessSlider: View {
    @EnvironmentObject var appState: AppState
    @State private var value = 0
    @State private var dragging = false

    var body: some View {
        LabeledSlider(
            label: "Brightness",
            value: $value,
            onLiveChange: { appState.onHold?($0) },
            onEditingBegan: { dragging = true },
            onCommit: {
                dragging = false
                appState.onHold?(value)
            }
        )
        .tint(appState.hold == nil ? nil : .orange)
        .onAppear { value = appState.autoBrightness }
        .onChange(of: appState.autoBrightness) { _, newValue in
            if !dragging { value = newValue }
        }
    }
}

// MARK: - End card

/// One end of Auto's range, in the preset card's shape: a row that expands to
/// its sliders. Dragging one shows that end on the monitor until the card
/// collapses, so you judge the value on the real screen.
private struct EndCard: View {
    let kind: AppState.EndKind
    let title: String
    @Binding var expanded: AppState.EndKind?

    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var draft = RoomLight.End(brightness: 0, contrast: 0)
    @State private var contrastLockedByHDR = false

    private var isExpanded: Bool { expanded == kind }
    private var isPreviewing: Bool { appState.previewingEnd == kind }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                editor
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
        .onAppear { draft = appState.end(kind) }
        .onChange(of: isExpanded) { _, nowExpanded in
            if !nowExpanded, isPreviewing { endPreview() }
            if nowExpanded { refreshHDR() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in refreshHDR() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isPreviewing ? Color.orange : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("br: \(draft.brightness)% · co: \(draft.contrast)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expanded = isExpanded ? nil : kind
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledSlider(
                label: "Brightness",
                value: $draft.brightness,
                onLiveChange: { _ in showOnMonitor() },
                onEditingBegan: { startPreview() },
                onCommit: { appState.setEnd(kind, draft) }
            )
            LabeledSlider(
                label: "Contrast",
                value: $draft.contrast,
                lockedNote: contrastLockedByHDR ? "Locked by monitor in HDR" : nil,
                onLiveChange: { _ in showOnMonitor() },
                onEditingBegan: { startPreview() },
                onCommit: { appState.setEnd(kind, draft) }
            )
            HStack {
                Button {
                    isPreviewing ? endPreview() : startPreview()
                } label: {
                    Label(isPreviewing ? "Previewing" : "Preview",
                          systemImage: isPreviewing ? "eye.fill" : "eye")
                }
                .controlSize(.small)
                .tint(isPreviewing ? .orange : nil)
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private func startPreview() {
        guard !isPreviewing else { return }
        appState.previewingEnd = kind
        showOnMonitor()
    }

    /// The live value goes to the monitor through Auto, which shows the end
    /// being previewed as is.
    private func showOnMonitor() {
        guard isPreviewing else { return }
        appState.setEnd(kind, draft, persist: false)
        appState.onAutoChanged?()
    }

    private func endPreview() {
        appState.previewingEnd = nil
        appState.onPreviewEnded?()
    }

    private func refreshHDR() {
        contrastLockedByHDR = HDRState.isOn(displayName: appState.displayName)
    }
}
