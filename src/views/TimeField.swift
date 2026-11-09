import SwiftUI
import AppKit

/// A time and its arrows, one look wherever Sundial asks for a time. A bare picker on its own
/// ground beside a separate stepper, because SwiftUI's picker put its text high in its field and
/// drew different arrows in the window than in the popup: "why is there no line on the popup one?"
struct TimeField: View {
    let label: String
    @Binding var time: Date
    @State private var picker = PickerHandle()

    var body: some View {
        HStack(spacing: 3) {
            BarePicker(label: label, time: $time, handle: picker)
                .fixedSize()
                .offset(y: Self.textDrop)
                .padding(.horizontal, Self.inset)
                .frame(height: Self.height)
                .modifier(FieldGround())
            Stepper(label, onIncrement: { picker.step(up: true) }, onDecrement: { picker.step(up: false) })
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
        }
        .fixedSize()
    }

    private static let height: CGFloat = 20
    private static let inset: CGFloat = 5
    /// Measured on the pixels, for the same room above and below the digits.
    private static let textDrop: CGFloat = 1.5
}

/// Clear inside its outline, so on the popup the popup's own glass shows through it, and in the
/// window the card's ground. A capsule of glass of its own read as "too rounded".
private struct FieldGround: ViewModifier {
    func body(content: Content) -> some View {
        content
            // A little darker than what's behind, "10 or 20%".
            .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)) }
    }
}

/// The picker the arrows act on. The arrows send it an arrow key, the one public way in, so they
/// step whichever of hour or minute is highlighted, as the system's own arrows do. With nothing
/// picked yet they start on the minute, the finer step and the one usually wanted.
@MainActor
private final class PickerHandle {
    weak var view: NSDatePicker?
    /// Whether a field has been picked, by the arrows or by a click. The picker remembers its field
    /// after the edit ends, so moving right every time would pass the minute to AM/PM.
    private var picked = false

    func step(up: Bool) {
        guard let view, let window = view.window else { return }
        if window.firstResponder === view {
            picked = true
        } else {
            window.makeFirstResponder(view)
            if !picked { press(NSRightArrowFunctionKey, code: 124); picked = true }
        }
        // The stepper's repeats while it's held all come under the press's own mouse-down, so a new
        // timestamp is a new press.
        let now = ProcessInfo.processInfo.systemUptime
        let stamp = NSApp.currentEvent?.timestamp ?? now
        if stamp != pressedAt { pressedAt = stamp; heldSince = now }
        let before = view.dateValue
        up ? press(NSUpArrowFunctionKey, code: 126) : press(NSDownArrowFunctionKey, code: 125)
        if now - heldSince > Self.speedUpAfter { speedUp(from: before, up: up) }
    }

    /// When a hold speeds up: the system's repeat is ten minutes a second, an hour every 6 seconds.
    static let speedUpAfter: TimeInterval = 1
    private var heldSince: TimeInterval = 0
    private var pressedAt: TimeInterval = -1

    /// Held long enough on the minute, the steps become 5 minutes, landing on :00, :05, :10. The hour
    /// steps as the system's arrows step it.
    private func speedUp(from before: Date, up: Bool) {
        guard let view else { return }
        let cal = Calendar.current
        func minute(_ d: Date) -> Int { let c = cal.dateComponents([.hour, .minute], from: d); return c.hour! * 60 + c.minute! }
        let was = minute(before), moved = (minute(view.dateValue) - was + 24 * 60) % (24 * 60)
        guard moved == 1 || moved == 24 * 60 - 1 else { return }
        let next = up ? (was / 5 + 1) * 5 : ((was + 4) / 5 - 1) * 5
        let wrapped = (next + 24 * 60) % (24 * 60)
        guard let date = cal.date(bySettingHour: wrapped / 60, minute: wrapped % 60, second: 0, of: before) else { return }
        view.dateValue = date
        if let action = view.action { NSApp.sendAction(action, to: view.target, from: view) }
    }

    private func press(_ arrow: Int, code: UInt16) {
        guard let view, let window = view.window else { return }
        let key = String(UnicodeScalar(arrow)!)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: key, charactersIgnoringModifiers: key,
                                           isARepeat: false, keyCode: code) else { return }
        view.keyDown(with: event)
    }
}

private struct BarePicker: NSViewRepresentable {
    let label: String
    @Binding var time: Date
    let handle: PickerHandle

    func makeCoordinator() -> Coordinator { Coordinator(time: $time) }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.controlSize = .small
        picker.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        picker.setAccessibilityLabel(label)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        // The binding is rebuilt with each keyframe a card shows, so one kept from before would
        // write the new time to the old keyframe.
        context.coordinator.time = $time
        handle.view = picker
        if picker.dateValue != time { picker.dateValue = time }
    }

    final class Coordinator: NSObject {
        var time: Binding<Date>
        init(time: Binding<Date>) { self.time = time }
        @MainActor @objc func changed(_ picker: NSDatePicker) { time.wrappedValue = picker.dateValue }
    }
}
