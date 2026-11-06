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
    /// Wider in a capsule, whose round ends would otherwise crowd the digits.
    private static var inset: CGFloat { if #available(macOS 26, *) { 8 } else { 5 } }
    /// Measured on the pixels, for the same room above and below the digits.
    private static let textDrop: CGFloat = 1.5
}

/// Glass where the system has it, as the window's buttons are, so the field sits with them.
private struct FieldGround: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.1)) }
            }
        }
    }
}

/// The picker the arrows act on. The arrows send it an arrow key, the one public way in, so they
/// step whichever of hour or minute is highlighted, as the system's own arrows do.
@MainActor
private final class PickerHandle {
    weak var view: NSDatePicker?

    func step(up: Bool) {
        guard let view, let window = view.window else { return }
        if window.firstResponder !== view { window.makeFirstResponder(view) }
        let key = String(UnicodeScalar(up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)!)
        guard let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: key, charactersIgnoringModifiers: key,
                                           isARepeat: false, keyCode: up ? 126 : 125) else { return }
        view.keyDown(with: press)
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
