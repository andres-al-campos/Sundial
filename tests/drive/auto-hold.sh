#!/bin/bash
# Drive: an evening hold outlives a relaunch. The slide Auto falls from is saved, and a new
# AutoController, as after an install or a login, starts from it. No monitor, no sensor.
set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/Library/Application Support/Sundial"

cat > "$work/main.swift" <<'SWIFT'
import Foundation

MainActor.assumeIsolated {
    guard AppState.supportDirectory.path.contains("/home/") else {
        print("✗ auto-hold: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    let held = AutoController.Slide(minute: 19 * 60 + 43, at: Date(), evening: true, brightness: 4, contrast: 11)
    AutoController.Slide.save(held)
    let relaunched = AutoController()
    guard relaunched.heldSlide == held else {
        print("✗ auto-hold: after a relaunch Auto starts from \(String(describing: relaunched.heldSlide)), not the hold at brightness 4. AutoController.slide has to start from Slide.saved(), or every install and login throws the evening's drag away and the screen jumps back up.")
        exit(1)
    }
    AutoController.Slide.save(nil)
    guard AutoController().heldSlide == nil else {
        print("✗ auto-hold: a cleared slide came back after a relaunch. Slide.save(nil) should remove auto-slide.json.")
        exit(1)
    }
    exit(0)
}
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift)
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/auto-hold" "$work/main.swift" $sources 2> "$work/err"; then
    echo "✗ auto-hold: the harness didn't compile. Update tests/drive/auto-hold.sh to match what changed:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
CFFIXED_USER_HOME="$work/home" "$work/auto-hold"
echo "✓ auto-hold: an evening hold is saved and a relaunched Auto starts from it"
