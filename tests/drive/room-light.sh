#!/bin/bash
# Drive: Auto's decisions from the room's light.
#
# Compiles the app's RoomLight with a harness and feeds it lux readings, so it
# runs without a sensor or a monitor. The cases use the readings logged on
# 2026-10-26 (lit room ~550, blinds shut ~35, a hand passing the notch spiking
# to 3000+). It can't see whether the sensor reads, or how the change feels on
# the monitor; dev/features/auto.md says how to check those by hand.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures: [String] = []
func check(_ what: String, _ ok: Bool, _ got: Any) {
    if !ok { failures.append("\(what): got \(got)") }
}

// Where the room sits.
check("a room at or below dark lux is fully dark", RoomLight.position(lux: 0) == 0 && RoomLight.position(lux: 5) == 0, RoomLight.position(lux: 0))
check("a room at or above bright lux is fully bright", RoomLight.position(lux: 500) == 1 && RoomLight.position(lux: 5000) == 1, RoomLight.position(lux: 5000))
let mid = RoomLight.position(lux: 50)
check("50 lux sits near the middle on a log scale", mid > 0.4 && mid < 0.6, mid)
let blinds = RoomLight.position(lux: 35), lit = RoomLight.position(lux: 550)
check("blinds shut sit well below the lit room", blinds < 0.5 && lit == 1, (blinds, lit))

// What the monitor gets.
let dark = RoomLight.End(brightness: 0, contrast: 7), bright = RoomLight.End(brightness: 42, contrast: 69)
let t0 = RoomLight.target(position: 0, dark: dark, bright: bright)
let t1 = RoomLight.target(position: 1, dark: dark, bright: bright)
check("a dark room gets the dark end", t0.brightness == 0 && t0.contrast == 7, t0)
check("a bright room gets the bright end", t1.brightness == 42 && t1.contrast == 69, t1)

// Gradual: shutting the blinds eases over minutes, not seconds.
var s = RoomLight.Smoother()
_ = s.add(lux: 240, dt: 1)
var after10 = 0.0, after180 = 0.0
for i in 1...180 {
    let v = s.add(lux: 35, dt: 1)
    if i == 10 { after10 = v }
    if i == 180 { after180 = v }
}
check("10s after the blinds shut, the average has barely started down", after10 > 120, after10)
check("3 minutes after, it has arrived", abs(after180 - 35) < 5, after180)

// A hand passing the notch hardly moves it.
var h = RoomLight.Smoother()
_ = h.add(lux: 500, dt: 1)
let spike = h.add(lux: 3300, dt: 1)
check("a 1s spike to 3300 lux moves the average under 10%", spike < 550, spike)

// The monitor's own easing.
check("a step is capped", RoomLight.step(10, toward: 20, maxStep: 0.5) == 10.5, RoomLight.step(10, toward: 20, maxStep: 0.5))
check("a step lands on a near target", RoomLight.step(10, toward: 10.3, maxStep: 0.5) == 10.3, RoomLight.step(10, toward: 10.3, maxStep: 0.5))
check("a step goes down too", RoomLight.step(10, toward: 0, maxStep: 0.5) == 9.5, RoomLight.step(10, toward: 0, maxStep: 0.5))

// A hand-set brightness holds, then lets go.
let start = Date(timeIntervalSince1970: 0)
let hold = RoomLight.Hold(brightness: 8, since: start, lux: 240)
check("a hold lasts with the room unchanged", !hold.isOver(now: start.addingTimeInterval(19 * 60), lux: 300), "over at 19 min")
check("a hold lapses after 20 minutes", hold.isOver(now: start.addingTimeInterval(20 * 60), lux: 240), "held at 20 min")
check("a hold ends when the room doubles", hold.isOver(now: start.addingTimeInterval(60), lux: 500), "held after doubling")
check("a hold ends when the room halves (blinds shut)", hold.isOver(now: start.addingTimeInterval(60), lux: 35), "held after blinds")

if !failures.isEmpty {
    failures.forEach { print("    \($0)") }
    exit(1)
}
SWIFT

if ! swiftc -o "$work/room" Sources/Control/RoomLight.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ room-light: the harness didn't compile. RoomLight's API probably changed; update tests/drive/room-light.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/room" > "$work/out"; then
    echo "✗ room-light: Auto decided wrongly. Fix it in Sources/Control/RoomLight.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
echo "✓ room-light: Auto maps the room to the two ends, eases over minutes, ignores a passing hand, and a hold lapses"
