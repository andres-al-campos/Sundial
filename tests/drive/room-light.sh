#!/bin/bash
# Drive: Auto's decisions from the room's light and the clock.
#
# Compiles the app's RoomLight with a harness and feeds it lux readings and
# times, so it runs without a sensor or a monitor. The lux cases use readings
# logged on 2026-10-26 (lit room ~550, blinds shut ~35, a hand passing the notch
# spiking to 3000+); the Night Shift and contrast cases are the presets the
# curves were fitted to. It can't see whether the sensor reads, or how the
# change feels on the monitor; dev/features/auto.md says how to check those.

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
func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

// Brightness: your level times the room.
let lvl = RoomLight.defaultLevel
check("the default level gives the Morning preset (42) in the lit room (550 lux)",
      near(RoomLight.brightness(level: lvl, lux: 550), 42, 1.5), RoomLight.brightness(level: lvl, lux: 550))
check("and about Night's 1 in a dark room (0.5 lux floors at 1)",
      RoomLight.brightness(level: lvl, lux: 0.5) < 3, RoomLight.brightness(level: lvl, lux: 0.5))
check("16x the light gives 4x the brightness",
      near(RoomLight.brightness(level: 10, lux: 1600) / RoomLight.brightness(level: 10, lux: 100), 4, 0.01), "")
check("brightness never passes 100", RoomLight.brightness(level: 80, lux: 10_000) == 100, RoomLight.brightness(level: 80, lux: 10_000))
// Setting a brightness keeps it: the level saved gives it back in the same room,
// and scales it in another.
let set = RoomLight.level(forBrightness: 8, lux: 240)
check("a set brightness comes back in the same room", near(RoomLight.brightness(level: set, lux: 240), 8, 0.001), RoomLight.brightness(level: set, lux: 240))
check("and is lower with the blinds shut", RoomLight.brightness(level: set, lux: 35) < 8, RoomLight.brightness(level: set, lux: 35))
check("a level can be set in a pitch-dark room", RoomLight.level(forBrightness: 5, lux: 0).isFinite, RoomLight.level(forBrightness: 5, lux: 0))

// Contrast follows brightness on the presets' line.
check("contrast at brightness 0 is Midnight's 7-8", near(RoomLight.contrast(brightness: 0), 7.8, 0.01), RoomLight.contrast(brightness: 0))
check("contrast at Morning's 42 is near its 69", near(RoomLight.contrast(brightness: 42), 69, 3), RoomLight.contrast(brightness: 42))

// Night Shift by the clock, against the presets it was fitted to.
func ns(_ h: Int, _ m: Int) -> Double { RoomLight.nightShift(minuteOfDay: h * 60 + m) }
check("off in the afternoon", ns(14, 47) == 0, ns(14, 47))
check("off just before the ramp", ns(17, 12) == 0, ns(17, 12))
check("near Twilight's 31 at 7:17 PM", near(ns(19, 17), 31, 4), ns(19, 17))
check("near Evening's 42 at 8:07 PM", near(ns(20, 7), 42, 4), ns(20, 7))
check("near Night's 67 at 10:17 PM", near(ns(22, 17), 67, 7), ns(22, 17))
check("near Midnight's 100 at 11:57 PM", near(ns(23, 57), 100, 5), ns(23, 57))
check("full after midnight", ns(3, 0) == 100, ns(3, 0))
check("off from 6:30 AM", ns(6, 30) == 0 && ns(6, 29) == 100, (ns(6, 29), ns(6, 30)))

// Easing: the blinds shutting (as logged, 237 → 35 lux over 8 s) lands in about
// 20 seconds: not instantly, and not dragging on.
var s = RoomLight.Smoother()
for _ in 0..<10 { _ = s.add(lux: 237, dt: 1) }
var after3 = 0.0, after25 = 0.0
for (i, v) in ([217, 192, 163, 206, 159, 72, 163, 41] + Array(repeating: 35, count: 30)).enumerated() {
    let avg = s.add(lux: Double(v), dt: 1)
    if i == 2 { after3 = avg }
    if i == 24 { after25 = avg }
}
check("3s into the blinds shutting, the average has barely moved", after3 > 180, after3)
check("25s in, it has arrived (within 15%)", after25 < 35 * 1.15, after25)

// A hand passing the notch doesn't move it at all.
var h = RoomLight.Smoother()
for _ in 0..<5 { _ = h.add(lux: 500, dt: 1) }
var peak = 0.0
for v in [3300.0, 500, 500, 500, 500] { peak = max(peak, h.add(lux: v, dt: 1)) }
check("a 1s spike to 3300 lux leaves the average where it was", near(peak, 500, 1), peak)
var d = RoomLight.Smoother()
for _ in 0..<5 { _ = d.add(lux: 500, dt: 1) }
var low = 1000.0
for v in [30.0, 500, 500, 500, 500] { low = min(low, d.add(lux: v, dt: 1)) }
check("and so does a 1s dip to 30 lux", near(low, 500, 1), low)

check("a step is capped", RoomLight.step(10, toward: 20, maxStep: 5) == 15, RoomLight.step(10, toward: 20, maxStep: 5))
check("a step lands on a near target", RoomLight.step(10, toward: 10.3, maxStep: 2) == 10.3, RoomLight.step(10, toward: 10.3, maxStep: 2))

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
echo "✓ room-light: brightness is your level times the room, a set level keeps, contrast and Night Shift match the fitted presets, it lands in ~20s, and a passing hand is ignored"
