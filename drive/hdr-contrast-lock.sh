#!/bin/bash
# Drive: contrast locks only when the configured display is in HDR.
#
# Compiles the app's own HDR decision with a small harness and feeds it screen
# lists, so it runs without a monitor. It can't see whether macOS reports the
# headroom it assumes, or how the greyed slider looks; features/presets.md
# says how to check those by hand.

set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

let m27qHDR = HDRState.Screen(name: "M27Q", potentialHeadroom: 4.18)
let m27qSDR = HDRState.Screen(name: "M27Q", potentialHeadroom: 1.0)
let builtIn = HDRState.Screen(name: "Built-in Retina Display", potentialHeadroom: 5.0)

let cases: [(String, String, [HDRState.Screen], Bool)] = [
    ("display in HDR locks",                         "M27Q", [m27qHDR, builtIn], true),
    ("display in SDR doesn't lock",                  "M27Q", [m27qSDR],          false),
    ("another screen's HDR doesn't lock this one",   "M27Q", [m27qSDR, builtIn], false),
    ("name matches partially, ignoring case",        "m27",  [m27qHDR],          true),
    ("no display name set doesn't lock",             "  ",   [m27qHDR, builtIn], false),
    ("display not connected doesn't lock",           "M27Q", [builtIn],          false),
]

var failed = false
for (what, name, screens, want) in cases {
    let got = HDRState.isOn(displayName: name, screens: screens)
    if got != want {
        print("    \(what): expected \(want), got \(got)")
        failed = true
    }
}
if failed { exit(1) }
SWIFT

if ! swiftc -o "$work/hdr" Sources/Control/HDRState.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ hdr-contrast-lock: the harness didn't compile. HDRState's signature probably changed; update drive/hdr-contrast-lock.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/hdr" > "$work/out"; then
    echo "✗ hdr-contrast-lock: HDRState.isOn decided wrongly. Fix it in Sources/Control/HDRState.swift:"
    cat "$work/out"
    exit 1
fi
echo "✓ hdr-contrast-lock: contrast locks only when the configured display is in HDR"
