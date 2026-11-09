#!/bin/bash
# Drive: opening or closing a preset card changes the list's scroll height once, so the scroll
# bar's handle resizes once instead of on every frame of the animation, and closing one at the end
# of the list glides it to its new end. Off-screen, taking no focus.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ scroll-once: the test hung. Check that PresetListView still renders in a plain window."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hung)
func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

@MainActor final class Open: ObservableObject { @Published var id: UUID? }
struct Host: View {
    @ObservedObject var open: Open
    let state: AppState
    var body: some View {
        // The card's own toggle sets the binding the same way: unanimated, the rows animating themselves.
        PresetListView(expandedPresetID: $open.id, appState: state, height: 552)
            .environmentObject(state)
            .frame(width: 700, height: 552, alignment: .top)
    }
}

Task { @MainActor in
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let state = AppState()
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ scroll-once: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    // Enough rows that the list scrolls, so the handle shows.
    for i in 0..<10 {
        let p = Preset(name: "P\(i)", hardwareBrightness: 50, hardwareContrast: 50, nightShift: 0)
        state.addPreset(p)
        state.addScheduleEntry(ScheduleEntry(presetID: p.id, hour: 2 * i + 1, minute: 0))
    }
    let open = Open()
    let w = NSWindow(contentRect: NSRect(x: -8000, y: 100, width: 700, height: 552), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: Host(open: open, state: state))
    w.orderFrontRegardless()
    await wait(1.0)
    func scroll(_ v: NSView) -> NSScrollView? { (v as? NSScrollView) ?? v.subviews.lazy.compactMap(scroll).first }
    guard let sv = scroll(w.contentView!) else { print("✗ scroll-once: no scroll view in PresetListView. Update tests/drive/scroll-once.sh if the list stopped scrolling."); exit(1) }
    var failures: [String] = []
    let target = state.schedule[state.schedule.count / 2].presetID
    for (name, id) in [("opening", Optional(target)), ("closing", nil), ("opening again", Optional(target))] {
        var heights: [CGFloat] = []
        let timer = Timer(timeInterval: 1.0 / 240, repeats: true) { _ in MainActor.assumeIsolated {
            let h = sv.documentView?.frame.height ?? -1
            if heights.last != h { heights.append(h) }
        }}
        RunLoop.main.add(timer, forMode: .common)
        await wait(0.05)
        open.id = id
        await wait(0.6)
        timer.invalidate()
        if heights.count > 2 {
            let shown = heights.prefix(6).map { String(format: "%.1f", $0) }.joined(separator: ", ")
            failures.append("\(name) a card changed the list's height \(heights.count - 1) times (\(shown)…), so the scroll bar's handle resized with it. PresetListView gives the scroll view its final height at once (finalHeight) and animates the rows inside it; a withAnimation around the change, or a wrong Row.expanded, brings the steps back.")
        }
    }
    // Closing a card while scrolled to the very end: the list glides to its new end, no step
    // more than a third of the way, and still changes height once.
    open.id = target
    await wait(0.6)
    let clip = sv.contentView
    clip.scroll(to: NSPoint(x: 0, y: (sv.documentView?.frame.height ?? 0) - clip.bounds.height))
    sv.reflectScrolledClipView(clip)
    await wait(0.3)
    var ys: [CGFloat] = [], heights: [CGFloat] = []
    let timer = Timer(timeInterval: 1.0 / 240, repeats: true) { _ in MainActor.assumeIsolated {
        if ys.last != clip.bounds.origin.y { ys.append(clip.bounds.origin.y) }
        let h = sv.documentView?.frame.height ?? -1
        if heights.last != h { heights.append(h) }
    }}
    RunLoop.main.add(timer, forMode: .common)
    await wait(0.05)
    open.id = nil
    await wait(0.6)
    timer.invalidate()
    let steps = zip(ys, ys.dropFirst()).map { abs($1 - $0) }
    let moved = abs((ys.last ?? 0) - (ys.first ?? 0))
    if moved == 0 || (steps.max() ?? 0) > moved / 3 {
        failures.append(String(format: "closing a card at the end of the list moved it %.0f points with a step of %.0f, a snap rather than a glide. PresetListView holds its height (held) while the card closes and scrolls to the new end with the rows; shrinking at once clamps the scroll position.", moved, steps.max() ?? 0))
    }
    if heights.count > 2 {
        failures.append("closing a card at the end of the list changed its height \(heights.count - 1) times; it should shrink once, after the rows settle.")
    }
    // Adding a preset with a card open, scrolled to the end: the new card opens at midnight, first in
    // the list and above the view, so the list glides up to it during the rows' own animation, and its height changes once.
    open.id = target
    await wait(0.6)
    clip.scroll(to: NSPoint(x: 0, y: (sv.documentView?.frame.height ?? 0) - clip.bounds.height))
    sv.reflectScrolledClipView(clip)
    await wait(0.3)
    var addYs: [(Double, CGFloat)] = [], addHeights: [CGFloat] = []
    let t0 = ProcessInfo.processInfo.systemUptime
    let addTimer = Timer(timeInterval: 1.0 / 240, repeats: true) { _ in MainActor.assumeIsolated {
        if addYs.last?.1 != clip.bounds.origin.y { addYs.append((ProcessInfo.processInfo.systemUptime - t0, clip.bounds.origin.y)) }
        let h = sv.documentView?.frame.height ?? -1
        if addHeights.last != h { addHeights.append(h) }
    }}
    RunLoop.main.add(addTimer, forMode: .common)
    await wait(0.05)
    let added = Preset(name: "New", hardwareBrightness: 70, hardwareContrast: 75, nightShift: 0)
    let addedAt = ProcessInfo.processInfo.systemUptime - t0
    state.addPreset(added)
    state.addScheduleEntry(ScheduleEntry(presetID: added.id, hour: 0, minute: 0))
    open.id = added.id
    await wait(0.8)
    addTimer.invalidate()
    let addSteps = zip(addYs, addYs.dropFirst()).map { abs($1.1 - $0.1) }
    let addMoved = abs((addYs.last?.1 ?? 0) - (addYs.first?.1 ?? 0))
    let settled = (addYs.last?.0 ?? 0) - addedAt
    if addMoved == 0 {
        failures.append("adding a preset whose card opens above the view didn't scroll to it. PresetListView's onChange of presets.count scrolls when the new card is out of view.")
    } else if (addSteps.max() ?? 0) > addMoved / 3 {
        failures.append(String(format: "adding a preset jumped the list %.0f points in one step of %.0f: it should glide to the new card.", addMoved, addSteps.max() ?? 0))
    } else if settled > 0.35 {
        failures.append(String(format: "adding a preset finished scrolling %.2fs after the add, after the rows had moved: the scroll has to run with the rows' 0.15s animation, not after it.", settled))
    }
    if addHeights.count > 2 {
        failures.append("adding a preset changed the list's height \(addHeights.count - 1) times; the scroll bar's handle should resize once.")
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ scroll-once:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/scroll-once" "$work/main.swift" tests/drive/support/off-screen.swift $sources 2> "$work/err"; then
    echo "✗ scroll-once: the harness didn't compile. Update tests/drive/scroll-once.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/scroll-once"
echo "✓ scroll-once: opening or closing a preset card changes the list's scroll height once, closing one at the end glides, and adding one glides to it in step with the rows"
