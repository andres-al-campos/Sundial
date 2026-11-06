#!/bin/bash
# Drive: the menu bar popup, built from the code as it is now, rendered off-screen in each tab,
# taking no focus. Nothing talks to the bridge, so no bulb moves.
#
#   ./build.sh drive popup                 checks it, keeps the PNGs nowhere
#   POPUP_OUT=dir ./build.sh drive popup   keeps them in dir
#
# SwiftUI's gestures take nothing off-screen, so a slider's drag isn't driven here.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=${POPUP_OUT:-$work/out}
mkdir -p "$out" "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ popup: the test hung before the popup rendered. Check MenuBarView still renders in an NSHostingView."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: hung)
func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

@MainActor func pixels(_ path: String) -> (colours: Int, orange: Int) {
    guard let d = FileManager.default.contents(atPath: path), let r = NSBitmapImageRep(data: d) else { return (0, 0) }
    var seen = Set<NSColor>(), orange = 0
    for y in stride(from: 0, to: r.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: r.pixelsWide, by: 2) {
            // The raw bytes: converting colour spaces moved the orange out of any range worth naming.
            var p = [Int](repeating: 0, count: 4)
            r.getPixel(&p, atX: x, y: y)
            seen.insert(NSColor(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[2]) / 255, alpha: 1))
            if p[0] > 180, p[2] < 120, p[0] - p[2] > 100 { orange += 1 }
        }
    }
    return (seen.count, orange)
}

Task { @MainActor in
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let out = CommandLine.arguments[1]
    let state = AppState()
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ popup: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    state.isSetUp = true
    func key(_ m: Int, _ b: Double, _ x: Double, _ y: Double) -> LightDay.Key { .init(minute: m, anchor: nil, on: true, brightness: b, x: x, y: y) }
    let day = [key(420, 30, 0.52, 0.41), key(720, 100, 0.34, 0.35), key(1260, 15, 0.60, 0.38)]
    state.lights = [.init(id: "a", deviceID: "da", name: "Lamp", keys: day), .init(id: "b", deviceID: "db", name: "Floor", keys: day)]
    // No bridge is reached: nothing here starts the LampController.
    state.hueHost = "bridge.test"
    state.lampStatus = "Paired · following the day"
    state.lampsFollow = true
    let held = ["b": LightDay.Hold(look: .init(on: true, brightness: 85, xy: .init(x: 0.25, y: 0.25)), until: Date().addingTimeInterval(3600))]

    var sizes: [String: CGSize] = [:], seen: [String: (colours: Int, orange: Int)] = [:]
    var failures: [String] = []
    let shots: [(String, AppState.PopupTab, [String: LightDay.Hold])] = [
        ("display", .display, [:]), ("display-held", .display, held),
        ("lighting", .lighting, [:]), ("lighting-held", .lighting, held),
    ]
    for (name, tab, holds) in shots {
        state.popupTab = tab
        state.holds = holds
        let host = NSHostingView(rootView: MenuBarView().environmentObject(state))
        let w = NSWindow(contentRect: NSRect(x: -8000, y: 100, width: 320, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        w.backgroundColor = NSColor(white: 0.17, alpha: 1)
        w.appearance = NSAppearance(named: .darkAqua)
        w.orderBack(nil)
        await wait(0.8)
        sizes[name] = host.fittingSize
        w.setContentSize(host.fittingSize)
        w.setFrameOrigin(NSPoint(x: -8000, y: 100))
        await wait(0.5)
        let path = "\(out)/\(name).png"
        if !capture(w, to: path) { failures.append("\(name): the popup couldn't be captured. See capture in tests/drive/support/off-screen.swift.") }
        seen[name] = pixels(path)
        if seen[name]!.colours < 20 { failures.append("\(name): the popup rendered blank. Something stopped MenuBarView drawing; see src/views/MenuBarView.swift.") }
        w.orderOut(nil)
    }
    state.holds = [:]
    if let a = seen["display"]?.orange, let b = seen["display-held"]?.orange, b <= a + 20 {
        failures.append("the Lighting tab's label isn't orange while a bulb is held (\(a) orange pixels without a hold, \(b) with). Segments in src/views/MenuBarView.swift colours the item MenuBarView passes as orange, from AppState.lampsOffTheDay.")
    }
    if sizes["lighting"] != sizes["lighting-held"] {
        failures.append("the Lighting tab changed size when a bulb was held (\(sizes["lighting"]!) to \(sizes["lighting-held"]!)). Its status line and button row have to keep one height whatever they show; see LightingPanel.status and .buttons.")
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ popup:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/popup" "$work/main.swift" tests/drive/support/off-screen.swift $sources 2> "$work/err"; then
    echo "✗ popup: the harness didn't compile. Update tests/drive/popup.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/popup" "$out"
echo "✓ popup: both tabs render off-screen, the Lighting label turns orange while a bulb is held, and a hold doesn't resize the popup${POPUP_OUT:+, PNGs in $POPUP_OUT}"
