#!/bin/bash
# Drive: a drag of Room Light's brightness slider reaches the monitor as it goes, not long after.
# A stand-in monitor takes 100ms a write, as DDC over I2C does; the drag sends a value every 15ms.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

final class SlowLink: DDCLink, @unchecked Sendable {
    let lock = NSLock()
    var writes: [(vcp: UInt8, value: UInt16, at: Date)] = []
    func write(display: String, vcp: UInt8, value: UInt16) -> Bool {
        usleep(100_000); lock.lock(); writes.append((vcp, value, Date())); lock.unlock(); return true
    }
    func read(display: String, vcp: UInt8) -> (current: Int, max: Int)? { nil }
    func monitors() -> [String] { ["Test"] }
}

Task { @MainActor in
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ auto-drag: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    let link = SlowLink()
    DDCController.link = link
    let state = AppState()
    state.isSetUp = true
    state.displayName = "Test"
    state.mode = .auto
    let auto = AutoController()
    auto.start(state: state, controller: DDCController(displayName: "Test"))
    try? await Task.sleep(for: .seconds(1))
    // A one-second drag from 10 to 70.
    for b in stride(from: 10, through: 70, by: 1) {
        auto.setBrightness(b, done: false)
        try? await Task.sleep(for: .milliseconds(15))
    }
    auto.setBrightness(70, done: true)
    let released = Date()
    try? await Task.sleep(for: .seconds(8))
    link.lock.lock(); let writes = link.writes; link.lock.unlock()
    let brightness = writes.filter { $0.vcp == 0x10 }
    guard let last = brightness.last, last.value == 70 else {
        print("✗ auto-drag: the monitor's last brightness was \(brightness.last.map { String($0.value) } ?? "none"), not the 70 the drag ended on. AutoController.write has to send each parameter's latest value."); exit(1)
    }
    let lag = last.at.timeIntervalSince(released)
    guard lag < 0.5 else {
        print(String(format: "✗ auto-drag: the monitor reached 70 %.1fs after the slider was let go, with %d writes queued behind the drag. AutoController.write should keep only each parameter's latest value while a write is out, as the schedule's sliders do (scheduleApply in PresetListView).", lag, writes.count)); exit(1)
    }
    exit(0)
}
RunLoop.main.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/auto-drag" "$work/main.swift" $sources 2> "$work/err"; then
    echo "✗ auto-drag: the harness didn't compile. Update tests/drive/auto-drag.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/auto-drag"
echo "✓ auto-drag: a brightness drag on a monitor that takes 100ms a write lands on its last value within half a second of letting go"
