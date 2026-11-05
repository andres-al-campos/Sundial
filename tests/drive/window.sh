#!/bin/bash
# Drive: the real window, built from the code as it is now, rendered off-screen to a PNG in dark and
# light, taking no focus. Nothing talks to the bridge, so no bulb moves.
#
#   ./build.sh drive window                  a made-up day; checks it renders, keeps the PNGs nowhere
#   WINDOW_OUT=dir ./build.sh drive window   keeps them in dir
#   WINDOW_REAL=1                            starts from a throwaway copy of your real config
#
# SwiftUI's gestures take nothing off-screen, so this shows the window at rest. Showing a card means
# calling the view's private functions from a scratch copy of src/.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=${WINDOW_OUT:-$work/out}
mkdir -p "$out" "$work/home/Library/Application Support/Sundial"
if [ -n "${WINDOW_REAL:-}" ]; then
    cp "$HOME/Library/Application Support/Sundial/config.json" "$work/home/Library/Application Support/Sundial/"
fi

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ window: the test hung before the window rendered. Check MainWindow.show still opens a window titled Sundial."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hung)
func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

/// A blank window also saves as a PNG, so count colours along a few rows of it. Below the title bar:
/// its traffic lights alone have enough colours to pass for a window with something in it.
@MainActor func colours(_ path: String) -> Int {
    guard let d = FileManager.default.contents(atPath: path), let r = NSBitmapImageRep(data: d), r.pixelsHigh > 0 else { return 0 }
    var seen = Set<NSColor>()
    for y in stride(from: r.pixelsHigh / 10, to: r.pixelsHigh, by: 7) {
        for x in stride(from: 0, to: r.pixelsWide, by: 3) { if let c = r.colorAt(x: x, y: y) { seen.insert(c) } }
    }
    return seen.count
}

Task { @MainActor in
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let out = CommandLine.arguments[1]
    let state = AppState()
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ window: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    if state.lights == nil {
        func key(_ m: Int, _ b: Double, _ x: Double, _ y: Double) -> LightDay.Key { .init(minute: m, anchor: nil, on: true, brightness: b, x: x, y: y) }
        state.lights = [.init(id: "a", deviceID: "da", name: "Lamp", keys: [key(420, 30, 0.52, 0.41), key(720, 100, 0.34, 0.35), key(1260, 15, 0.60, 0.38)])]
    }
    state.lampStatus = "Paired · following the day"
    state.lampsFollow = true
    state.windowSection = .lights
    MainWindow.show(state)
    await wait(1.0)
    guard let w = NSApp.windows.first(where: { $0.title == "Sundial" }) else {
        print("✗ window: no window titled Sundial after MainWindow.show. Update this test if the window's title changed."); exit(1)
    }
    w.setFrame(NSRect(x: -8000, y: 100, width: 1014, height: 652), display: true)
    var failures: [String] = []
    for (name, look) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
        w.appearance = NSAppearance(named: look)
        await wait(0.9)
        let path = "\(out)/lights-\(name).png"
        if !capture(w, to: path) {
            failures.append("\(name): the window couldn't be captured. See capture in tests/drive/support/off-screen.swift.")
        } else if colours(path) < 20 {
            failures.append("\(name): the window rendered blank (\(colours(path)) colours). Something stopped the Lights section drawing; see src/views/LightsView.swift.")
        }
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ window:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/window" "$work/main.swift" tests/drive/support/off-screen.swift $sources 2> "$work/err"; then
    echo "✗ window: the harness didn't compile. Update tests/drive/window.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/window" "$out"
echo "✓ window: the Lights window renders in dark and light, off-screen, taking no focus${WINDOW_OUT:+, PNGs in $WINDOW_OUT}"
