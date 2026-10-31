import AppKit

/// Ends a text or time edit when the user clicks anything else in Sundial's
/// windows. SwiftUI's empty space and plain views don't take keyboard focus,
/// so an hour or minute stayed selected until the panel was rebuilt. A
/// background tap fixed Auto but not the Schedule cards, whose list catches
/// the clicks first; watching every click covers both.
enum EditFocus {
    private static var monitor: Any?

    static func endOnOtherClicks() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window, let content = window.contentView,
                  window.firstResponder is NSText || window.firstResponder is NSDatePicker
                    || window.firstResponder is NSTextField else { return event }
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            if !isEditable(hit) { window.makeFirstResponder(nil) }
            return event
        }
    }

    /// True for a text field, a time picker, or something inside one.
    private static func isEditable(_ view: NSView?) -> Bool {
        var v = view
        while let current = v {
            if current is NSTextField || current is NSText || current is NSDatePicker { return true }
            v = current.superview
        }
        return false
    }
}
