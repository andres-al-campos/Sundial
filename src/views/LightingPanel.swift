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
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.lampStatus.hasPrefix("Paired") ? "Reading your bulbs…" : appState.lampStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if appState.keychainDeclined {
                        Button("Allow Keychain Access") { appState.onAllowKeychain?() }
                            .font(.subheadline)
                            .hoverShade()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                TimelineView(.everyMinute) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        status
                        ForEach(bulbs) { row($0) }
                        buttons.padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
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
                let set = appState.holdLamp(bulb.id, from: look) {
                    // Dragging a bulb switched off brings it on: more light is what the drag asks for.
                    $0.on = true
                    $0.brightness = max(1, b)
                }
                // Paused, nothing holds it, so this is where the slider learns where the bulb is.
                if !appState.lampsFollow { read[bulb.id] = set }
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

    /// What the list as a whole is doing, over it as the window's "Now" line is. One line whatever
    /// the state. A hold says itself in its bulb's orange name and in Return to schedule.
    private var status: some View {
        Group {
            if appState.keychainDeclined {
                // One line, as every status here is, so the popup keeps its size.
                Button("Allow Keychain Access so the lights follow the day") { appState.onAllowKeychain?() }
                    .buttonStyle(.link)
            } else if appState.lampsPaused {
                Text("Paused").foregroundStyle(.orange)
            } else if let next = nextKey {
                Text("Next color key at \(LightsView.time(next))").foregroundStyle(.secondary)
            } else {
                Text(appState.lampStatus).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .frame(height: 14)
    }

    /// A row of their own. Pause holds the left and a hold's button comes in to its right, into
    /// empty space, so nothing moves when it does.
    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                appState.toggleLampsFollow()
            } label: {
                Text(appState.lampsFollow ? "Pause" : "Resume")
            }
            .buttonStyle(.outlined(appState.lampsPaused ? .orange : .primary))
            if !appState.holds.isEmpty {
                Button {
                    appState.returnLampsToSchedule { read = [:] }
                } label: {
                    Text("Return to schedule")
                }
                .buttonStyle(.outlined(.orange))
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        // The footer's size, so the popup's buttons are one size.
        .font(.subheadline)
        .frame(height: OutlinedButtonStyle.height)
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
            Button("Pair Hue Bridge…") { appState.onPairLamps?() }
                .buttonStyle(.outlined(HoverButton.createBlue))
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
