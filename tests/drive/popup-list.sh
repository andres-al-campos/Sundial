#!/bin/bash
# Drive: a popup's open list sits on the button's edges, with the chosen item over the label.
#
# Opens the real list and measures its window against the button, taking no focus. macOS moves a
# list opened off-screen onto the nearest display, so for under half a second a small window and its
# list show in the screen's bottom-left corner. Renders of the closed button looked right
# through four lists that opened off its edges, since what was wrong only showed once open.
# POPUP_OUT=dir keeps PNGs of the button and the open list.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=${POPUP_OUT:-$work}

cat > "$work/main.swift" <<'SWIFT'
import SwiftUI
import AppKit

let app = NSApplication.shared
let hung = DispatchWorkItem { print("✗ popup-list: the test hung with the list open. It closes the list with cancelTracking from a timer in the event-tracking run loop mode; check that still runs."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: hung)

@MainActor func find(_ v: NSView) -> NSPopUpButton? { (v as? NSPopUpButton) ?? v.subviews.lazy.compactMap(find).first }
func save(_ id: Int, _ path: String) {
    guard let img = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(id), [.bestResolution, .boundsIgnoreFraming]) else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

Task { @MainActor in
    let out = CommandLine.arguments[1]
    let labels = ["Every day at this time", "1 hr 30 min after sunset", "4 hr 50 min before bedtime"]
    stayOutOfTheWay()
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let view = PopUp(items: labels, selected: 1) { _ in }
        .controlSize(.small).frame(width: 192).fixedSize(horizontal: false, vertical: true).padding(20)
    let screen = NSScreen.main!.visibleFrame
    let w = NSWindow(contentRect: NSRect(x: screen.minX + 20, y: screen.minY + 120, width: 232, height: 60),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .darkAqua)
    w.contentView = NSHostingView(rootView: view)
    w.orderFrontRegardless()
    try? await Task.sleep(for: .seconds(0.3))
    guard let b = find(w.contentView!) else { print("✗ popup-list: no NSPopUpButton inside PopUp. Update tests/drive/popup-list.sh if PopUp changed."); exit(1) }
    let button = w.convertToScreen(b.convert(b.bounds, to: nil))
    save(w.windowNumber, "\(out)/button.png")
    var failures: [String] = []
    var lists = 0
    let t = Timer(timeInterval: 0.25, repeats: false) { _ in
        MainActor.assumeIsolated {
            for list in NSApp.windows where list !== w && list.isVisible {
                lists += 1
                save(list.windowNumber, "\(out)/list.png")
                let f = list.frame
                if abs(f.minX - button.minX) > 0.5 || abs(f.maxX - button.maxX) > 0.5 {
                    failures.append("the list spans x \(f.minX)–\(f.maxX), the button \(button.minX)–\(button.maxX). EdgePopUpButton in src/views/PopUp.swift opens it at the button's left edge with minimumWidth set to its width; AppKit's own placement lines the item's text up instead, which moves the list.")
                }
                if let item = b.selectedItem, let i = b.menu?.index(of: item), i >= 0 {
                    // Items are equal height, so the chosen one's top is a fraction of the list's height.
                    let n = CGFloat(b.menu!.items.count)
                    let rows = f.height - 10   // the list's padding, 5 above and 5 below on macOS 26
                    let itemTop = f.maxY - 5 - rows / n * CGFloat(i)
                    if abs(itemTop - button.maxY) > 3 {
                        failures.append("the chosen item's top is at y \(itemTop), the button's at \(button.maxY). It should open over the label, as a popup does.")
                    }
                }
            }
            b.menu?.cancelTracking()
        }
    }
    RunLoop.main.add(t, forMode: .eventTracking)
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: button.midX - w.frame.minX, y: button.midY - w.frame.minY),
                                   modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    b.mouseDown(with: click)
    if lists == 0 { failures.append("no list opened. EdgePopUpButton.mouseDown in src/views/PopUp.swift should pop the menu up.") }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier != front {
        failures.append("this test took focus from the frontmost app. It has to stay out of the way: see stayOutOfTheWay in tests/drive/support/off-screen.swift, and what in opening a menu activates the app.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ popup-list:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
app.run()
SWIFT

if ! swiftc -target arm64-apple-macos14 -o "$work/popup-list" "$work/main.swift" tests/drive/support/off-screen.swift src/views/PopUp.swift 2> "$work/err"; then
    echo "✗ popup-list: the harness didn't compile. PopUp's signature probably changed; update tests/drive/popup-list.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
"$work/popup-list" "$out"
echo "✓ popup-list: a popup's list opens on the button's edges, the chosen item over the label${POPUP_OUT:+, PNGs in $POPUP_OUT}"
