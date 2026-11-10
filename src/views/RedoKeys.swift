import AppKit

/// Cmd-Y and Control-Y redo in the window as Shift-Cmd-Z does, for hands used to them from
/// elsewhere: "i kind of like ctrl y too". Control-Y is left to a text field, where it pastes
/// what Control-K cut.
@MainActor
enum RedoKeys {
    private static var monitor: Any?
    private static weak var window: NSWindow?

    static func install(for window: NSWindow) {
        self.window = window
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { redo(event) ? nil : event }
        }
    }

    private static func redo(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, event.charactersIgnoringModifiers?.lowercased() == "y" else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let inText = window.firstResponder is NSText
        guard mods == .command || (mods == .control && !inText) else { return false }
        guard let undo = window.firstResponder?.undoManager ?? window.undoManager, undo.canRedo else { return false }
        undo.redo()
        return true
    }
}
