#!/bin/bash
# Drive: a drag of Room Light's brightness slider reaches the monitor as it goes, not long after.
# A stand-in monitor takes 10ms a write, as the M27Q does (measured 2026-11-19); the drag sends a value
# every 15ms. Values in the middle go once and at once, and the one let go on goes twice to stay.
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
        usleep(10_000); lock.lock(); writes.append((vcp, value, Date())); lock.unlock(); return true
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
    guard lag < 0.2 else {
        print(String(format: "✗ auto-drag: the monitor reached 70 %.2fs after the slider was let go, with %d writes in all. AutoController.write should keep only each parameter's latest value while a write is out, and a drag's values shouldn't wait between writes (DDCController.setPercent).", lag, writes.count)); exit(1)
    }
    let during = brightness.filter { $0.at < released }
    let gaps = zip(during, during.dropFirst()).map { $1.at.timeIntervalSince($0.at) }.sorted()
    let typical = gaps.isEmpty ? 1 : gaps[gaps.count / 2]
    guard typical < 0.03 else {
        print(String(format: "✗ auto-drag: during the drag the monitor's brightness changed every %.0fms. With a 10ms monitor it should be under 30: a drag's values go once, with no wait after (applySingle with final: false).", typical * 1000)); exit(1)
    }
    let repeats = Dictionary(grouping: during, by: { $0.value }).values.filter { $0.count > 1 }.count
    guard repeats <= 1 else {
        print("✗ auto-drag: \(repeats) values in the middle of the drag were sent more than once. They should go once (final: false); only the value let go on goes twice."); exit(1)
    }
    guard brightness.filter({ $0.value == 70 && $0.at >= released }).count >= 2 else {
        print("✗ auto-drag: the value let go on, 70, wasn't sent twice after the release. It's the one that stays, so it goes as final, as MonitorControl sends every value: a monitor busy with the last one can drop it. See AutoController.write's settled."); exit(1)
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
echo "✓ auto-drag: on a monitor that takes 10ms a write, a brightness drag moves the monitor every few milliseconds, sending each value once, and lands on the last, sent twice, within 0.2s of letting go"
