import SwiftUI

/// The popup's lights: each bulb as it is now, with a brightness slider for when you need more
/// light than the day gives. A drag moves the bulb as it goes and holds it until sunrise, as the
/// window's card does. Why a bulb is where it is lives in the window, a click on its name away.
struct LightingPanel: View {
    @EnvironmentObject var appState: AppState
    /// The bulbs as last read from the bridge. Until the read lands, the day's or the hold's.
    @State private var read: [String: LightDay.State] = [:]
    @State private var dragging = false

    private var bulbs: [LightDay.Bulb] { appState.lights ?? [] }

    var body: some View {
        Group {
            if appState.hueHost == nil {
                unpaired
            } else if bulbs.isEmpty {
                Text(appState.lampStatus.hasPrefix("Paired") ? "Reading your bulbs…" : appState.lampStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                TimelineView(.everyMinute) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(bulbs) { row($0) }
                        footer
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear { readLamps() }
        .onDisappear {
            // Closed mid-drag: the hold stays, and the bulb settles to it.
            if dragging { appState.onEndLampPreview?() }
        }
    }

    private var nowMinute: Double {
        let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: Date())
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func now(_ id: String) -> LightDay.State { appState.lampNow(id, read: read, at: nowMinute) }

    private func readLamps() {
        Task { if let lamps = try? await appState.onReadLamps?() { read = lamps } }
    }

    // MARK: - A bulb

    private func row(_ bulb: LightDay.Bulb) -> some View {
        let look = now(bulb.id)
        let held = appState.lampHoldOwner(bulb.id) != nil
        let c = LightDay.rgb(look.xy)
        return HStack(spacing: 8) {
            Button {
                NSApp.keyWindow?.close()
                appState.windowSection = .lights
                appState.onOpenWindow?()
            } label: {
                HStack(spacing: 6) {
                    // Its true colour, which the slider beside it doesn't change.
                    Circle()
                        .fill(look.on ? Color(red: c.r, green: c.g, blue: c.b) : Color(white: 0.3))
                        .frame(width: 10, height: 10)
                        .overlay { Circle().stroke(.black.opacity(0.4), lineWidth: 0.5) }
                    Text(bulb.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(held ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                }
                .frame(width: 72, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(bulb.name) in Sundial")
            // The sun says what the slider moves, as Control Center's display slider does.
            Image(systemName: "sun.min")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { look.on ? look.brightness : 0 }, set: { b in
                appState.holdLamp(bulb.id, from: look) {
                    // Dragging a bulb switched off brings it on: more light is what the drag asks for.
                    $0.on = true
                    $0.brightness = max(1, b)
                }
            }), in: 0...100, onEditingChanged: { editing in
                dragging = editing
                if !editing { appState.onEndLampPreview?() }
            })
            .controlSize(.small)
            Text(look.on ? "\(Int(look.brightness.rounded()))%" : "Off")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 20)
    }

    // MARK: - The day

    /// One line whatever the state, so a hold starting or ending doesn't resize the popup.
    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if !appState.holds.isEmpty {
                    Text("Held until sunrise").foregroundStyle(.orange)
                } else if appState.lampsPaused {
                    Text("Paused").foregroundStyle(.orange)
                } else if let next = nextKey {
                    Text("Next color key at \(LightsView.time(next))").foregroundStyle(.secondary)
                } else {
                    Text(appState.lampStatus).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !appState.holds.isEmpty {
                HoverButton("Return to schedule", rest: .orange) {
                    read = [:]
                    appState.returnLampsToSchedule()
                }
                .transition(.opacity)
            }
            HoverButton(appState.lampsFollow ? "Pause" : "Resume", rest: appState.lampsPaused ? .orange : .secondary) {
                appState.toggleLampsFollow()
            }
        }
        .font(.caption)
        .frame(height: 20)
        .animation(.easeOut(duration: 0.15), value: appState.holds.isEmpty)
    }

    /// When the next color key comes, across every bulb's day.
    private var nextKey: Int? {
        let marks = appState.lampMarks, at = Int(nowMinute)
        let minutes = bulbs.filter { $0.parent == nil }.flatMap { $0.keys.map { LightDay.minute(of: $0, marks: marks) } }
        return minutes.min { LightDay.wrap($0 - at - 1) < LightDay.wrap($1 - at - 1) }
    }

    // MARK: - Unpaired

    private var unpaired: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sundial can fade Hue lamps along with the day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HoverButton("Pair Hue Bridge…", rest: HoverButton.createBlue) { appState.onPairLamps?() }
                .font(.subheadline)
            if appState.lampStatus != "Not paired" {
                Text(appState.lampStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}
