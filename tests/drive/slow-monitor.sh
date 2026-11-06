#!/bin/bash
# Drive: Sundial's monitor commands against a stand-in monitor that takes 2 seconds a write, as
# one busy over I2C might. The main thread has to keep answering, and the values have to land in
# the order they were sent.
#
#   ./build.sh drive slow-monitor

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

final class SlowLink: DDCLink, @unchecked Sendable {
    var written: [UInt16] = []
    func write(display: String, vcp: UInt8, value: UInt16) -> Bool { sleep(2); written.append(value); return true }
    func read(display: String, vcp: UInt8) -> (current: Int, max: Int)? { nil }
    func monitors() -> [String] { ["Test"] }
}

let hung = DispatchWorkItem { print("✗ slow-monitor: the test hung. A write never came back; see onQueue in src/control/DDCController.swift."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 40, execute: hung)

Task { @MainActor in
    let link = SlowLink()
    DDCController.link = link
    let ddc = DDCController(displayName: "Test")
    var failures: [String] = []
    // Ticks on the main thread while the writes are out. A write waited for here stops them.
    var longest: TimeInterval = 0, last = Date()
    let ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        MainActor.assumeIsolated {
            longest = max(longest, Date().timeIntervalSince(last))
            last = Date()
        }
    }
    // A few milliseconds apart, as a drag's values come.
    var sends: [Task<Void, Never>] = []
    for v in 1...3 {
        sends.append(Task { await ddc.applySingle("hardwareBrightness", value: v * 10) })
        try? await Task.sleep(for: .milliseconds(20))
    }
    for s in sends { await s.value }
    ticker.invalidate()
    if longest > 0.5 {
        failures.append("the main thread stopped for \(String(format: "%.1f", longest))s while the monitor was slow. Every write has to go through onQueue, off the main thread, in src/control/DDCController.swift.")
    }
    if link.written != [10, 20, 30] {
        failures.append("the values landed as \(link.written), not 10, 20, 30 in the order sent. The writes share one serial queue in DDCController so a drag's last value is the one that stays, and a monitor that answers no reads is taken to top out at 100.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ slow-monitor:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
RunLoop.main.run()
SWIFT

if ! swiftc -target arm64-apple-macos14 -o "$work/drive" "$work/main.swift" src/control/DDCController.swift src/control/DDC.swift src/control/NightShiftController.swift src/models/*.swift 2> "$work/err"; then
    echo "✗ slow-monitor: the harness didn't compile. Update tests/drive/slow-monitor.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
"$work/drive"
echo "✓ slow-monitor: with the monitor taking 2s a write, the main thread keeps answering and the values land in the order sent"
