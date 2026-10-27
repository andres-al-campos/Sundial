import SwiftUI

/// Auto mode's panel: how bright the room is, the two controls (brightness,
/// which you set once and the room scales, and contrast, which follows
/// brightness at the multiple you set), and Night Shift by the clock.
///
/// Every row has a fixed height whatever the state, so the sensor dropping out
/// never resizes the popup.
struct AutoView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            room
            AutoSlider(label: "Brightness", current: appState.autoBrightness) { appState.onSetBrightness?($0, $1) }
            AutoSlider(label: "Contrast", current: appState.autoContrast) { appState.onSetContrast?($0, $1) }
            row("Night Shift", "\(appState.autoNightShift)% · warms \(time(RoomLight.warmFrom)) → \(time(RoomLight.warmFull)), off \(time(RoomLight.warmOff))")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var room: some View {
        HStack(spacing: 8) {
            Text("Room")
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            if let lux = appState.roomLux {
                RoomMeter(position: RoomLight.meterPosition(lux: lux))
                    .opacity(appState.sensorReading ? 1 : 0.4)
                // Same width as the sliders' values below, so the meter and the
                // sliders end at one line.
                Text(appState.sensorReading ? Self.luxText(lux) : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
                    .help(appState.sensorReading ? "Lux, from the light sensor beside the camera" : "No reading: the lid may be closed")
            } else {
                Text("No reading yet: the lid may be closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(height: 20)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }

    /// Tenths below 10 lux, where the sensor tells them apart; whole lux above.
    static func luxText(_ lux: Double) -> String {
        lux < 9.95 ? String(format: "%.1f", lux) : "\(Int(lux.rounded()))"
    }

    private func time(_ minuteOfDay: Int) -> String {
        var c = DateComponents()
        c.hour = (minuteOfDay / 60) % 24
        c.minute = minuteOfDay % 60
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return Calendar.current.date(from: c).map { f.string(from: $0) } ?? ""
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

// MARK: - Sliders

/// One of Auto's two controls. Dragging moves the monitor at once, and the
/// value is kept: Sundial stores it as a rule (your level for brightness, a
/// multiple of brightness for contrast) so other rooms scale from it. Between
/// drags it shows what Auto has the monitor at.
private struct AutoSlider: View {
    let label: String
    let current: Int
    /// The value, and true when the drag ends.
    let onSet: (Int, Bool) -> Void
    @State private var value = 0
    @State private var dragging = false

    var body: some View {
        LabeledSlider(
            label: label,
            value: $value,
            onLiveChange: { onSet($0, false) },
            onEditingBegan: { dragging = true },
            onCommit: {
                dragging = false
                onSet(value, true)
            }
        )
        .frame(height: 20)
        .onAppear { value = current }
        .onChange(of: current) { _, newValue in
            if !dragging { value = newValue }
        }
    }
}
