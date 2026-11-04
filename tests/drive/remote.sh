#!/bin/bash
# Drive: which sundial:// URLs mean what, and what a wrong one says. Compiles the
# app's parser with a harness, so it runs without the app. Whether the app carries
# them out takes the installed app: dev/features/cli.md says how.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures: [String] = []
func means(_ url: String, _ want: RemoteCommand) {
    let got = RemoteCommand.parse(URL(string: url)!)
    if got != .success(want) { failures.append("\(url) should mean \(want): got \(got)") }
}
func refused(_ url: String, saying word: String) {
    guard case .failure(let f) = RemoteCommand.parse(URL(string: url)!) else {
        failures.append("\(url) should be refused"); return
    }
    if !f.message.contains(word) { failures.append("\(url) should say \(word): said \(f.message)") }
}

means("sundial://status?id=1", .status)
means("sundial://lights/pause", .pauseLights)
means("sundial://lights/resume", .resumeLights)
means("sundial://mode/auto", .auto)
means("sundial://mode/schedule", .schedule)
means("sundial://open", .open(nil))
means("sundial://open/presets?id=1", .open(.presets))
means("sundial://brightness/40", .brightness(40))
means("sundial://contrast/0", .contrast(0))
means("sundial://lights/read", .readLights)
means("sundial://lights/load", .loadLights)
means("sundial://hue", .readHue)
means("sundial://screenshot", .screenshot)
refused("sundial://brightness/101", saying: "0 to 100")
refused("sundial://brightness/low", saying: "0 to 100")
refused("sundial://open/lamps", saying: "lights, presets or settings")
refused("sundial://dance", saying: "Use status")
refused("http://status", saying: "Use status")
if WindowSection.ID.self != WindowSection.self {
    failures.append("WindowSection's id must be WindowSection itself: a List only selects rows whose id has its selection's type, so the window's sidebar ignores clicks otherwise")
}

if !failures.isEmpty {
    failures.forEach { print("    \($0)") }
    exit(1)
}
SWIFT

if ! swiftc -o "$work/remote" src/control/RemoteCommand.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ remote: the harness didn't compile. RemoteCommand's API probably changed; update tests/drive/remote.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/remote" > "$work/out"; then
    echo "✗ remote: a sundial:// URL means the wrong thing. Fix it in src/control/RemoteCommand.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
if ! grep -q 'fullSizeContentView' src/views/MainWindow.swift; then
    echo "✗ remote: MainWindow's NSWindow lost .fullSizeContentView. Without it a NavigationSplitView's title bar blur lands on the content's top 50pt, hiding what's there. Put it back in the style mask in src/views/MainWindow.swift."
    exit 1
fi
if ! grep -q 'makeFirstResponder(nil)' src/views/MainWindow.swift; then
    echo "✗ remote: MainWindow no longer clears the first responder when it opens. With keyboard navigation on, AppKit focuses the first button, and its ring reads as that button being on. Put window?.makeFirstResponder(nil) back after makeKeyAndOrderFront in src/views/MainWindow.swift."
    exit 1
fi
if grep -q 'contentMinSize' src/views/MainWindow.swift || ! grep -q 'frame(minWidth: minSize.width' src/views/MainWindow.swift; then
    echo "✗ remote: MainWindow's minimum size has to be a frame on its root view. An NSHostingView replaces the window's contentMinSize with what the view asks for, which let the window shrink to 334 x 153 and piled the hour labels on each other. Put .frame(minWidth: minSize.width, minHeight: minSize.height) back on the root view in src/views/MainWindow.swift."
    exit 1
fi
if ! grep -q 'forKey: "windowSection"' src/AppState.swift; then
    echo "✗ remote: AppState no longer keeps windowSection in UserDefaults, so the window would forget which section it was closed in. Read it in the property's initial value and write it in didSet, in src/AppState.swift."
    exit 1
fi
echo "✓ remote: every sundial:// command parses to what it says, a wrong one is refused saying what would work, and the window's sidebar can select, its top row stays clear of the title bar, it can't shrink below its minimum, and it reopens on the section it closed in"
