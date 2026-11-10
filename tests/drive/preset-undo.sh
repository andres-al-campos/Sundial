#!/bin/bash
# Drive: Cmd-Z on the presets page. Each change to a preset is one undo, with its time, a held
# time arrow is one, an undo touches only the preset it's for, a deleted preset comes back opened,
# and Shift-Cmd-Z redoes. Off-screen, taking no focus.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ preset-undo: the test hung. Check that PresetListView still renders in a plain window."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hung)
func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

final class UndoKeeper: NSObject, NSWindowDelegate {
    let undo: UndoManager
    init(_ undo: UndoManager) { self.undo = undo }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }
}
@MainActor final class Open: ObservableObject { @Published var id: UUID? }
struct Host: View {
    @ObservedObject var open: Open
    let state: AppState
    var body: some View {
        PresetListView(expandedPresetID: $open.id, appState: state, height: 552)
            .environmentObject(state)
            .frame(width: 700, height: 552, alignment: .top)
    }
}

NSSetUncaughtExceptionHandler { e in
    print("✗ preset-undo: \(e.reason ?? e.name.rawValue). If this came from a held time arrow, its later steps registered an undo of their own: PresetsHistory.change with merging should join them to the first.")
    exit(1)
}
Task { @MainActor in
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let state = AppState()
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ preset-undo: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    var ids: [UUID] = []
    for i in 0..<4 {
        let p = Preset(name: "P\(i)", hardwareBrightness: 50, hardwareContrast: 50, nightShift: 0)
        state.addPreset(p)
        state.addScheduleEntry(ScheduleEntry(presetID: p.id, hour: 3 * i + 6, minute: 0))
        ids.append(p.id)
    }
    let open = Open()
    let w = NSWindow(contentRect: NSRect(x: -8000, y: 100, width: 700, height: 552), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: Host(open: open, state: state))
    // The window's, through its delegate, as the list's views get it.
    let undo = UndoManager()
    let keeper = UndoKeeper(undo)
    w.delegate = keeper
    guard w.undoManager === undo else { print("✗ preset-undo: the window doesn't take its undo manager from its delegate, so the test can't watch Cmd-Z."); exit(1) }
    // A group per click, as AppKit makes one per event. The held arrow's later steps get none:
    // they should register nothing, and if they do, the undo manager throws (caught below).
    undo.groupsByEvent = false
    func step(_ name: String, grouped: Bool = true, _ body: () -> Void) async {
        if grouped { undo.beginUndoGrouping() }
        body()
        if grouped { undo.endUndoGrouping() }
        await wait(0.03)
    }
    w.orderFrontRegardless()
    await wait(0.8)
    var failures: [String] = []
    @MainActor func brightness(_ id: UUID) -> Int? { state.preset(for: id)?.hardwareBrightness }
    @MainActor func time(_ id: UUID) -> Int? { state.schedule.first { $0.presetID == id }?.minutesSinceMidnight }

    // A slider on one preset, then one on another: undoing the second leaves the first.
    await step("a") { PresetsHistory.change(ids[0], "Change Brightness", in: state, undo: undo) { var p = state.preset(for: ids[0])!; p.hardwareBrightness = 80; state.updatePreset(p) } }
    await step("b") { PresetsHistory.change(ids[1], "Change Brightness", in: state, undo: undo) { var p = state.preset(for: ids[1])!; p.hardwareBrightness = 20; state.updatePreset(p) } }
    undo.undo()
    if brightness(ids[1]) != 50 || brightness(ids[0]) != 80 {
        failures.append("undoing a brightness change left P1 at \(brightness(ids[1]) ?? -1) and P0 at \(brightness(ids[0]) ?? -1); it should put P1 back to 50 and leave P0 at 80. PresetsHistory keeps each preset as it was before its change.")
    }
    undo.redo()
    if brightness(ids[1]) != 20 { failures.append("redo didn't bring P1's brightness back to 20 (it's \(brightness(ids[1]) ?? -1)). PresetsHistory registers the redo when it undoes.") }

    // A held arrow: many time steps in a row, one undo.
    for m in 1...12 {
        await step("t\(m)", grouped: m == 1) { PresetsHistory.change(ids[2], "Change Time", in: state, undo: undo, merging: true) {
            var e = state.schedule.first { $0.presetID == ids[2] }!; e.minute = m; state.updateScheduleEntry(e) } }
    }
    undo.undo()
    if time(ids[2]) != 12 * 60 {
        failures.append("one undo after twelve time steps in a row put P2 at minute \(time(ids[2]) ?? -1) of the day, not back at 12:00. A held arrow should be one undo: PresetsHistory.change with merging.")
    }

    // Deleting the open card, then undoing: the preset comes back with its time, opened.
    open.id = ids[3]
    await wait(0.4)
    await step("d") { PresetsHistory.change(ids[3], "Delete Preset", in: state, undo: undo) { state.deletePreset(id: ids[3]) } }
    await wait(0.4)
    undo.undo()
    await wait(0.4)
    if state.preset(for: ids[3]) == nil || time(ids[3]) != 15 * 60 {
        failures.append("undoing a delete didn't bring P3 back at 15:00 (preset \(state.preset(for: ids[3]) == nil ? "missing" : "back"), time \(time(ids[3]) ?? -1)). PresetsHistory restores the preset and its schedule entries together.")
    }
    if open.id != ids[3] {
        failures.append("the preset brought back by undo didn't open. PresetListView's onChange of presets.count opens one that appears.")
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift.")
    }
    // Cmd-Y and Control-Y redo too, through the window's key handling.
    RedoKeys.install(for: w)
    for (key, flags) in [("Cmd-Y", NSEvent.ModifierFlags.command), ("Control-Y", .control)] {
        await step("y") { PresetsHistory.change(ids[0], "Change Brightness", in: state, undo: undo) { var p = state.preset(for: ids[0])!; p.hardwareBrightness = 33; state.updatePreset(p) } }
        undo.undo()
        let y = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: w.windowNumber, context: nil, characters: "y", charactersIgnoringModifiers: "y", isARepeat: false, keyCode: 16)!
        NSApp.sendEvent(y)
        await wait(0.05)
        if brightness(ids[0]) != 33 {
            failures.append("\(key) didn't redo (P0's brightness is \(brightness(ids[0]) ?? -1), not 33). RedoKeys.install watches the window's key presses.")
        }
    }
    _ = keeper
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ preset-undo:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/preset-undo" "$work/main.swift" tests/drive/support/off-screen.swift $sources 2> "$work/err"; then
    echo "✗ preset-undo: the harness didn't compile. Update tests/drive/preset-undo.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/preset-undo"
echo "✓ preset-undo: each preset change is one undo with its time, a held arrow is one, an undo touches only its preset, a deleted preset comes back opened, and redo redoes, from Cmd-Y and Control-Y too"
