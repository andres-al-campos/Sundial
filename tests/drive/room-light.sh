#!/bin/bash
# Drive: Auto's decisions from the room's light and the clock.
#
# Compiles the app's RoomLight with a harness and feeds it lux readings and
# times, so it runs without a sensor or a monitor. The lux cases use readings
# logged on 2026-10-26 (lit room ~550, blinds shut ~35, night 0-3, a hand passing
# the notch spiking to 3000+) and the brightnesses set that evening; the Night Shift and contrast cases are the presets the
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

// Brightness: your level times the room, fitted to the brightnesses set on
// 2026-10-26's evening.
let lvl = RoomLight.defaultLevel
func b(_ lux: Double) -> Double { RoomLight.brightness(level: lvl, lux: lux) }
check("the default level gives the 17-22 set at night (2 lux)", b(2) >= 15 && b(2) <= 22, b(2))
check("and the 25-30 set at dusk (19-32 lux)", b(19) >= 25 && b(32) <= 36, (b(19), b(32)))
check("and the 40 set at 84 lux", near(b(84), 40, 5), b(84))
check("a reading of 0 counts as 0.1 lux, the darkest measured, not black", b(0) == b(0.1) && b(0) > 5, b(0))
check("the LED's dark settings (0.15, 2.2, 7 lux) give three different brightnesses", b(0.15) + 3 < b(2.2) && b(2.2) + 3 < b(7), (b(0.15), b(2.2), b(7)))
check("16x the light gives 2x the brightness",
      near(RoomLight.brightness(level: 10, lux: 1600) / RoomLight.brightness(level: 10, lux: 100), 2, 0.01), "")
check("the level is the brightness at 100 lux", near(RoomLight.brightness(level: 30, lux: 100), 30, 0.001), "")
check("level 0 is the monitor's darkest in any room",
      RoomLight.brightness(level: 0, lux: 2000) == 0 && RoomLight.contrast(brightness: 0) == 0, "")
check("brightness never passes 100", RoomLight.brightness(level: 80, lux: 10_000) == 100, RoomLight.brightness(level: 80, lux: 10_000))
// Setting a brightness keeps it: the level saved gives it back in the same room,
// and scales it in another.
let set = RoomLight.level(forBrightness: 8, lux: 240)
check("a set brightness comes back in the same room", near(RoomLight.brightness(level: set, lux: 240), 8, 0.001), RoomLight.brightness(level: set, lux: 240))
check("and is lower with the blinds shut", RoomLight.brightness(level: set, lux: 35) < 8, RoomLight.brightness(level: set, lux: 35))
check("a brightness set at night saves a level that is sane by day", RoomLight.brightness(level: RoomLight.level(forBrightness: 17, lux: 2), lux: 550) < 80, RoomLight.brightness(level: RoomLight.level(forBrightness: 17, lux: 2), lux: 550))

// Contrast is π × brightness to start, so both reach 0 together.
check("contrast at brightness 0 is 0", RoomLight.contrast(brightness: 0) == 0, RoomLight.contrast(brightness: 0))
check("contrast at 20 is about 63, near the 3-4x dragged to", near(RoomLight.contrast(brightness: 20), 62.8, 0.1), RoomLight.contrast(brightness: 20))
check("contrast never passes 100", RoomLight.contrast(brightness: 90) == 100, RoomLight.contrast(brightness: 90))
let k = RoomLight.contrastScale(forContrast: 30, brightness: 20)
check("a set contrast comes back at the same brightness", near(RoomLight.contrast(brightness: 20, scale: k), 30, 0.001), RoomLight.contrast(brightness: 20, scale: k))
check("and scales with brightness", near(RoomLight.contrast(brightness: 10, scale: k), 15, 0.001), RoomLight.contrast(brightness: 10, scale: k))
check("contrast can be set at brightness 0", RoomLight.contrastScale(forContrast: 5, brightness: 0).isFinite, RoomLight.contrastScale(forContrast: 5, brightness: 0))

// Night Shift by the clock, against the presets it was fitted to.
func ns(_ h: Int, _ m: Int) -> Double { RoomLight.nightShift(minuteOfDay: h * 60 + m) }
check("off in the afternoon", ns(14, 47) == 0, ns(14, 47))
check("off just before the ramp", ns(17, 12) == 0, ns(17, 12))
check("near Twilight's 31 at 7:17 PM", near(ns(19, 17), 31, 4), ns(19, 17))
check("near Evening's 42 at 8:07 PM", near(ns(20, 7), 42, 4), ns(20, 7))
check("near Night's 67 at 10:17 PM", near(ns(22, 17), 67, 8), ns(22, 17))
check("near Midnight's 100 at 11:57 PM", near(ns(23, 57), 100, 5), ns(23, 57))
check("full after midnight", ns(3, 0) == 100, ns(3, 0))
check("off from 6:30 AM", ns(6, 30) == 0 && ns(6, 29) == 100, (ns(6, 29), ns(6, 30)))

// The dark: below what the sensor sees, the clock dims to the night minimum by
// bedtime (the fitted schedule: warming from 5:13 PM, full at midnight, off 6:30 AM).
let night = RoomLight.fittedSchedule
func dk(_ h: Int, _ m: Int, since sh: Int, _ sm: Int) -> Double {
    RoomLight.darkFraction(minuteOfDay: h * 60 + m, darkSince: sh * 60 + sm, schedule: night)
}
check("dark at 10:30 PM starts at the room's brightness", dk(22, 30, since: 22, 30) == 0, dk(22, 30, since: 22, 30))
check("and is halfway at 11:15", near(dk(23, 15, since: 22, 30), 0.5, 0.001), dk(23, 15, since: 22, 30))
check("and at the minimum by bedtime and after", dk(0, 0, since: 22, 30) == 1 && dk(3, 0, since: 22, 30) == 1, (dk(0, 0, since: 22, 30), dk(3, 0, since: 22, 30)))
check("going dark after bedtime is the minimum at once", dk(1, 0, since: 1, 0) == 1, dk(1, 0, since: 1, 0))
check("a dark morning after Night Shift ends isn't dimmed", dk(7, 0, since: 22, 30) == 0, dk(7, 0, since: 22, 30))
check("a dark afternoon isn't dimmed", dk(14, 0, since: 13, 0) == 0, dk(14, 0, since: 13, 0))
check("dark since before the evening counts from its start", near(dk(20, 36, since: 15, 0), 0.5, 0.01), dk(20, 36, since: 15, 0))
let litB = RoomLight.brightness(level: 15, lux: 0)
check("the dark's minimum is reached at bedtime", RoomLight.brightness(level: 15, lux: 0, dark: 1, nightMinimum: 1) == 1, "")
check("halfway, halfway between", near(RoomLight.brightness(level: 15, lux: 0, dark: 0.5, nightMinimum: 1), (litB + 1) / 2, 0.001), litB)
check("a room already dimmer than the minimum isn't brightened",
      RoomLight.brightness(level: 2, lux: 0, dark: 1, nightMinimum: 1) == RoomLight.brightness(level: 2, lux: 0), "")
let darkLevel = RoomLight.level(forBrightness: 2, lux: 0, dark: 0.5, nightMinimum: 1)
check("a brightness set halfway into the dark comes back there",
      near(RoomLight.brightness(level: darkLevel, lux: 0, dark: 0.5, nightMinimum: 1), 2, 0.001), darkLevel)

// Contrast in the dark goes to the night contrast, not a multiple of 0.
check("at bedtime in the dark, contrast is the night contrast",
      RoomLight.contrast(litBrightness: 4, scale: 4, dark: 1, nightContrast: 3) == 3, "")
check("halfway, halfway between", near(RoomLight.contrast(litBrightness: 4, scale: 4, dark: 0.5, nightContrast: 3), 9.5, 0.001),
      RoomLight.contrast(litBrightness: 4, scale: 4, dark: 0.5, nightContrast: 3))
check("lit, it's the multiple", RoomLight.contrast(litBrightness: 10, scale: 4, dark: 0, nightContrast: 3) == 40, "")
check("a contrast drag at brightness 0 doesn't set the multiple (the 'one to one' of 2026-10-31)",
      RoomLight.contrastScale(forContrast: 1, litBrightness: 0, dark: 0, nightContrast: 3) == nil, "")
check("nor at bedtime in the dark, where it sets the night contrast",
      RoomLight.contrastScale(forContrast: 5, litBrightness: 10, dark: 1, nightContrast: 3) == nil, "")
if let k2 = RoomLight.contrastScale(forContrast: 9.5, litBrightness: 4, dark: 0.5, nightContrast: 3) {
    check("a contrast set halfway into the dark comes back there",
          near(RoomLight.contrast(litBrightness: 4, scale: k2, dark: 0.5, nightContrast: 3), 9.5, 0.001), k2)
} else { check("a contrast can be set halfway into the dark", false, "nil") }

// The sun, at the point macOS's time zone table gives America/Chicago.
let chi = RoomLight.coordinates(iso6709: "+415100-0873900")
check("the zone table's point parses", chi != nil && near(chi!.latitude, 41.85, 0.001) && near(chi!.longitude, -87.65, 0.001), chi as Any)
func sun(_ y: Int, _ m: Int, _ d: Int, _ off: Double) -> RoomLight.SunTimes? {
    RoomLight.sunTimes(year: y, month: m, day: d, latitude: 41.85, longitude: -87.65, utcOffset: off)
}
if let june = sun(2026, 6, 21, -5), let dec = sun(2026, 12, 21, -6) {
    check("Chicago's June solstice: sunrise ~5:15, sunset ~8:29 PM", near(june.sunrise, 315, 3) && near(june.sunset, 20 * 60 + 29, 3), june)
    check("Chicago's December solstice: sunrise ~7:15, sunset ~4:22 PM", near(dec.sunrise, 435, 3) && near(dec.sunset, 16 * 60 + 22, 3), dec)
    let w = RoomLight.warmSchedule(sun: dec)
    check("in December Night Shift starts warming earlier and stays full to bedtime", w.from < RoomLight.fittedSchedule.from && w.full == RoomLight.fittedSchedule.full, w)
} else { check("Chicago has a sunrise and sunset", false, "nil") }
if let today = sun(2026, 10, 26, -5) {
    let w = RoomLight.warmSchedule(sun: today)
    check("on the day it was fitted, the sun's schedule is the fitted one (±2 min)",
          abs(w.from - RoomLight.fittedSchedule.from) <= 2 && abs(w.off - RoomLight.fittedSchedule.off) <= 2, w)
}
check("no sun times, the fitted schedule", RoomLight.warmSchedule(sun: nil) == RoomLight.fittedSchedule, "")
check("a 23:00 bedtime is full warmth at 23:00", RoomLight.nightShift(minuteOfDay: 23 * 60, schedule: RoomLight.warmSchedule(sun: nil, bedtime: 23 * 60)) == 100, "")
check("a 1:00 bedtime is the same night, not before warming starts", RoomLight.warmSchedule(sun: nil, bedtime: 60).full == 25 * 60, RoomLight.warmSchedule(sun: nil, bedtime: 60))

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

if ! swiftc -o "$work/room" src/control/RoomLight.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ room-light: the harness didn't compile. RoomLight's API probably changed; update tests/drive/room-light.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/room" > "$work/out"; then
    echo "✗ room-light: Auto decided wrongly. Fix it in src/control/RoomLight.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
echo "✓ room-light: brightness is your level times the room's fourth root, fitted to tonight's settings, a set level keeps, contrast is a multiple of brightness you can set, a dark room dims to the night brightness and contrast by bedtime, a contrast drag at brightness 0 leaves the multiple alone, Night Shift matches the fitted presets and follows Chicago's sun, it lands in ~20s, and a passing hand is ignored"
