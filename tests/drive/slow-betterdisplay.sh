#!/bin/bash
# Drive: Sundial's monitor commands against a stand-in BetterDisplay that takes 2 seconds a call,
# as the real one does (about 16) when its app isn't running. The main thread has to keep
# answering, and the values have to land in the order they were sent.
#
#   ./build.sh drive slow-betterdisplay

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/BetterDisplay" <<'FAKE'
#!/bin/bash
sleep 2
echo "$*" >> "$(dirname "$0")/calls.log"
FAKE
chmod +x "$work/BetterDisplay"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

let hung = DispatchWorkItem { print("✗ slow-betterdisplay: the test hung. A BetterDisplay call never came back; see capture in src/control/DDCController.swift."); exit(1) }
DispatchQueue.global().asyncAfter(deadline: .now() + 40, execute: hung)

Task { @MainActor in
    let cli = CommandLine.arguments[1]
    let ddc = DDCController(cliPath: cli, displayName: "Test")
    var failures: [String] = []
    // Ticks on the main thread while the calls are out. A call waited for here stops them.
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
        failures.append("the main thread stopped for \(String(format: "%.1f", longest))s while BetterDisplay was slow. Every call has to go through capture, off the main thread, in src/control/DDCController.swift.")
    }
    let log = (try? String(contentsOfFile: (cli as NSString).deletingLastPathComponent + "/calls.log", encoding: .utf8)) ?? ""
    let values = log.split(separator: "\n").compactMap { $0.split(separator: "=").last.map(String.init) }
    if values != ["10%", "20%", "30%"] {
        failures.append("the values landed as \(values), not in the order sent. The calls share one serial queue in DDCController so a drag's last value is the one that stays.")
    }
    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ slow-betterdisplay:")
    failures.forEach { print("    \($0)") }
    exit(1)
}
RunLoop.main.run()
SWIFT

if ! swiftc -target arm64-apple-macos14 -o "$work/drive" "$work/main.swift" src/control/DDCController.swift src/control/NightShiftController.swift src/models/*.swift 2> "$work/err"; then
    echo "✗ slow-betterdisplay: the harness didn't compile. Update tests/drive/slow-betterdisplay.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
"$work/drive" "$work/BetterDisplay"
echo "✓ slow-betterdisplay: with BetterDisplay taking 2s a call, the main thread keeps answering and the values land in the order sent"
