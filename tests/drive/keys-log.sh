#!/bin/bash
# Drive: a change to a bulb's color keys lands in keys-log.jsonl, after a first line per bulb with
# where it started, and a change that moves nothing writes nothing. No window, no bridge.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

MainActor.assumeIsolated {
    let state = AppState()
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ keys-log: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    let key = LightDay.Key(minute: 600, anchor: nil, on: true, brightness: 40, x: 0.5, y: 0.41)
    state.lights = [.init(id: "a", deviceID: "da", name: "Lamp", keys: [key]), .init(id: "b", deviceID: "db", name: "Floor", keys: [key])]
    let history = LightsHistory()
    history.attach(state)
    history.commit(nil, "Nothing")
    state.lights![0].keys[0].minute = 660
    history.commit(nil, "Move Color Key")
    let text = (try? String(contentsOf: KeysLog.url, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n").compactMap { try? JSONDecoder().decode(KeysLog.Line.self, from: Data($0.utf8)) }
    var failures: [String] = []
    if lines.map(\.change) != ["Start of log", "Start of log", "Move Color Key"] {
        failures.append("keys-log.jsonl has \(lines.map(\.change)); it should start with each bulb's keys, then only the change that moved one (a commit that changed nothing writes nothing). KeysLog.write is called from LightsHistory.finish.")
    }
    if let last = lines.last, last.bulb != "Lamp" || last.keys.first?.minute != 660 {
        failures.append("the logged change is \(last.bulb) at minute \(last.keys.first?.minute ?? -1); it should be Lamp's keys after the move, with its key at 660.")
    }
    if failures.isEmpty { exit(0) }
    print("✗ keys-log:"); failures.forEach { print("    \($0)") }
    exit(1)
}
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/keys-log" "$work/main.swift" $sources 2> "$work/err"; then
    echo "✗ keys-log: the harness didn't compile. Update tests/drive/keys-log.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/keys-log"
echo "✓ keys-log: a color key change is logged with the bulb's keys after it, from a first line per bulb, and a commit that moves nothing logs nothing"
