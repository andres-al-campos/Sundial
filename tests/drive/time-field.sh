#!/bin/bash
# Drive: the time field's arrows, wherever Sundial asks for a time.
#
# Clicks the real field off-screen, never taking focus, through the event queue so EditFocus
# sees the clicks too. It can't see how the field looks, which is the design's to decide.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ time-field: the test hung, so a click never finished. A stepper tracks the mouse until it sees a release; check the test still posts one."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hung)

final class Model: ObservableObject {
    @Published var first = at(10, 30)
    @Published var second = at(18, 5)
    @Published var usingSecond = false
    static func at(_ h: Int, _ m: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())! }
}
struct Root: View {
    @ObservedObject var m: Model
    var body: some View {
        // One field whose binding moves on, as the card's does from keyframe to keyframe.
        TimeField(label: "Time", time: m.usingSecond ? $m.second : $m.first)
            .frame(width: 300, height: 100)
    }
}
@MainActor func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? { (v as? T) ?? v.subviews.lazy.compactMap { find($0, t) }.first }
func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

var failures: [String] = []
Task { @MainActor in
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    EditFocus.endOnOtherClicks()
    let m = Model()
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: Root(m: m))
    w.makeKeyAndOrderFront(nil)
    w.makeFirstResponder(nil)
    await wait(0.6)
    guard let picker = find(w.contentView!, NSDatePicker.self), let stepper = find(w.contentView!, NSStepper.self) else {
        print("✗ time-field: no picker or stepper in TimeField. A drive of its arrows needs an NSDatePicker and an NSStepper; update this test if the field changed."); exit(1)
    }
    let box = stepper.convert(stepper.bounds, to: nil)
    @MainActor func click(up: Bool) async {
        let at = NSPoint(x: box.midX, y: up ? box.minY + box.height * 0.75 : box.minY + box.height * 0.25)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.postEvent(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!, atStart: false)
        }
        await wait(0.35)
    }
    @MainActor func hold(up: Bool, for seconds: Double) async {
        let at = NSPoint(x: box.midX, y: up ? box.minY + box.height * 0.75 : box.minY + box.height * 0.25)
        func post(_ type: NSEvent.EventType) {
            NSApp.postEvent(NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!, atStart: false)
        }
        post(.leftMouseDown)
        // The stepper tracks the press in a loop of its own, so the release has to come from outside it.
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { DispatchQueue.main.async { post(.leftMouseUp) } }
        await wait(seconds + 0.4)
    }
    func expect(_ what: String, _ date: Date, _ h: Int, _ min: Int, fix: String) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        if c.hour != h || c.minute != min { failures.append("\(what): expected \(h):\(min), got \(c.hour ?? -1):\(c.minute ?? -1). \(fix)") }
    }
    await click(up: true)
    expect("up with nothing highlighted", m.first, 10, 31, fix: "With nothing picked the arrows start on the minute. Check PickerHandle.step in TimeField.swift.")
    if w.firstResponder !== picker { failures.append("after an arrow the picker isn't focused, so nothing shows what the arrows step. Check PickerHandle.step in TimeField.swift.") }
    await click(up: false)
    expect("down", m.first, 10, 30, fix: "Check PickerHandle.step in TimeField.swift.")
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    picker.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                          context: nil, characters: left, charactersIgnoringModifiers: left, isARepeat: false, keyCode: 123)!)
    await wait(0.1)
    await click(up: true)
    expect("up with the hour highlighted", m.first, 11, 30, fix: "The arrows must step what's highlighted. EditFocus ends the edit on this click and PickerHandle.step starts it again, which relies on the picker remembering its field and on step moving to the minute only before anything was picked. If the minute moved, one of those broke.")
    m.usingSecond = true
    await wait(0.3)
    expect("a new binding shown", picker.dateValue, 18, 5, fix: "TimeField's updateNSView has to show the time it's given.")
    await click(up: true)
    expect("a new binding written", m.second, 19, 5, fix: "TimeField's updateNSView has to hand the coordinator the current binding, or an arrow writes to the keyframe shown before.")
    expect("the old binding left alone", m.first, 11, 30, fix: "TimeField's updateNSView has to hand the coordinator the current binding, or an arrow writes to the keyframe shown before.")
    // Held on the minute, the steps become 5 minutes after a second; a click after is one minute again.
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    picker.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                          context: nil, characters: right, charactersIgnoringModifiers: right, isARepeat: false, keyCode: 124)!)
    await wait(0.1)
    let start = Calendar.current.dateComponents([.hour, .minute], from: m.second)
    await hold(up: true, for: 2.2)
    let held = Calendar.current.dateComponents([.hour, .minute], from: m.second)
    let moved = (held.hour! * 60 + held.minute!) - (start.hour! * 60 + start.minute!)
    if held.minute! % 5 != 0 || moved < 40 {
        failures.append("holding the up arrow 2 seconds from \(start.hour!):\(start.minute!) reached \(held.hour!):\(held.minute!), \(moved) minutes. After PickerHandle.speedUpAfter the steps should be 5 minutes, landing on multiples of 5. Check speedUp in TimeField.swift, and that a hold's repeats still share the press's mouse-down timestamp.")
    }
    await click(up: true)
    let after = Calendar.current.dateComponents([.hour, .minute], from: m.second)
    if (after.hour! * 60 + after.minute!) - (held.hour! * 60 + held.minute!) != 1 {
        failures.append("a click after a hold moved \(held.hour!):\(held.minute!) to \(after.hour!):\(after.minute!), not one minute. A new press has to start slow again; check heldSince in TimeField.swift.")
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ time-field:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

if ! swiftc -target arm64-apple-macos14 -o "$work/time-field" "$work/main.swift" tests/drive/support/off-screen.swift \
    src/views/TimeField.swift src/views/EditFocus.swift 2> "$work/err"; then
    echo "✗ time-field: the harness didn't compile. TimeField's signature probably changed; update tests/drive/time-field.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
"$work/time-field"
echo "✓ time-field: the arrows start on the minute, then step what's highlighted, a held arrow speeds up to 5 minutes and a click after is 1, on whichever time the field shows"
