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

// Brightness before sunset: your level times the room, fitted to the settled
// daytime drags of 2026-10-27 to 11-01.
let lvl = RoomLight.defaultLevel
func b(_ lux: Double) -> Double { RoomLight.brightness(level: lvl, lux: lux) }
check("the default level gives about the 25 set at 35-51 lux", b(35) >= 15 && b(51) <= 25, (b(35), b(51)))
check("and about the 29-42 set at 96-143 lux", b(96) >= 25 && b(143) <= 42, (b(96), b(143)))
check("and about the 74 set at 470 lux", near(b(470), 74, 12), b(470))
check("a reading of 0 counts as 0.1 lux, the darkest measured", b(0) == b(0.1), b(0))
check("4x the light gives 2x the brightness",
      near(RoomLight.brightness(level: 10, lux: 400) / RoomLight.brightness(level: 10, lux: 100), 2, 0.01), "")
check("the level is the brightness at 100 lux", near(RoomLight.brightness(level: 30, lux: 100), 30, 0.001), "")
check("level 0 is the monitor's darkest in any room",
      RoomLight.brightness(level: 0, lux: 2000) == 0 && RoomLight.contrast(brightness: 0) == 0, "")
check("brightness never passes 100", RoomLight.brightness(level: 80, lux: 10_000) == 100, RoomLight.brightness(level: 80, lux: 10_000))
// Setting a brightness keeps it: the level saved gives it back in the same room,
// and scales it in another.
let set = RoomLight.level(forBrightness: 8, lux: 240)
check("a set brightness comes back in the same room", near(RoomLight.brightness(level: set, lux: 240), 8, 0.001), RoomLight.brightness(level: set, lux: 240))
check("and is lower with the blinds shut", RoomLight.brightness(level: set, lux: 35) < 8, RoomLight.brightness(level: set, lux: 35))

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

// The evening: the sensor reads the lamps then, so the clock takes the screen to
// the night pair by bedtime (the fitted schedule: from 5:13 PM, full at midnight,
// off 6:30 AM).
let night = RoomLight.fittedSchedule
func dk(_ h: Int, _ m: Int, since sh: Int, _ sm: Int) -> Double {
    RoomLight.eveningFraction(minuteOfDay: h * 60 + m, since: sh * 60 + sm, schedule: night)
}
func eve(_ h: Int, _ m: Int) -> Bool { RoomLight.isEvening(minuteOfDay: h * 60 + m, schedule: night) }
check("the afternoon is before the evening", !eve(17, 12) && !eve(6, 30), (eve(17, 12), eve(6, 30)))
check("Night Shift's start, midnight and 6:29 AM are the evening", eve(17, 13) && eve(0, 0) && eve(6, 29), "")
check("the evening starts at the room's brightness", dk(17, 13, since: 17, 13) == 0, dk(17, 13, since: 17, 13))
check("and is halfway halfway to bedtime", near(dk(20, 36, since: 17, 13), 0.5, 0.01), dk(20, 36, since: 17, 13))
check("and at the night pair by bedtime and after", dk(0, 0, since: 17, 13) == 1 && dk(3, 0, since: 17, 13) == 1, (dk(0, 0, since: 17, 13), dk(3, 0, since: 17, 13)))
check("a drag at 10:30 PM starts the slide over from there", dk(22, 30, since: 22, 30) == 0 && near(dk(23, 15, since: 22, 30), 0.5, 0.001), dk(23, 15, since: 22, 30))
check("waking after bedtime is the night pair at once", dk(1, 0, since: 1, 0) == 1, dk(1, 0, since: 1, 0))
check("the morning after Night Shift ends isn't on the slide", dk(7, 0, since: 22, 30) == 0, dk(7, 0, since: 22, 30))
check("nor is the afternoon", dk(14, 0, since: 13, 0) == 0, dk(14, 0, since: 13, 0))
check("a start from before the evening counts from its start", near(dk(20, 36, since: 15, 0), 0.5, 0.01), dk(20, 36, since: 15, 0))
check("the evening's length is Night Shift's hours", RoomLight.eveningLength(schedule: night) == 13 * 60 + 17, RoomLight.eveningLength(schedule: night))
check("the slide reaches the night value at bedtime", RoomLight.slid(5, toward: 1, dark: 1) == 1, "")
check("halfway, halfway between", RoomLight.slid(5, toward: 1, dark: 0.5) == 3, "")
check("a value already below the night's isn't raised", RoomLight.slid(0.5, toward: 1, dark: 1) == 0.5, "")
// Only a lit room before sunset says anything about the day. Each of the others
// crushed the next morning's level until 2026-11-01: brightness 1 at 0 lux saved a
// level of 5.6, or 6.2 at 23:30.
func tgt(_ lux: Double, evening: Bool, _ f: Double) -> RoomLight.DragTarget { RoomLight.dragTarget(lux: lux, evening: evening, fraction: f) }
check("a drag before sunset in a lit room saves the day's level, even a dim one", tgt(2, evening: false, 0) == .day, "")
check("a drag in the evening holds, however bright the lamps read", tgt(0, evening: true, 0.09) == .hold && tgt(133, evening: true, 0.1) == .hold, "")
check("after bedtime it sets the night pair, whatever the lamps read", tgt(0, evening: true, 1) == .nightPair && tgt(30, evening: true, 1) == .nightPair, "")
check("a dark daytime room's drag holds, at the sensor's floor too", tgt(0, evening: false, 0) == .hold && tgt(0.1, evening: false, 0) == .hold, "")
check("a contrast drag at brightness 0 doesn't set the multiple (the 'one to one' of 2026-10-31)",
      RoomLight.savedContrastScale(forContrast: 1, brightness: 0) == nil, "")
check("at brightness 10 it does", RoomLight.savedContrastScale(forContrast: 40, brightness: 10) == 4, "")

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
// A place picked on the map.
let austin = RoomLight.sunTimes(year: 2026, month: 11, day: 2, latitude: 30, longitude: -98, utcOffset: -6)
check("a picked place changes the sun: 30° N, 98° W sets near 5:43 PM on 2026-11-02, not Chicago's 4:44", austin.map { near($0.sunset, 17 * 60 + 43, 3) } ?? false, austin as Any)
let clicked = WorldMap.place(x: 260, y: 76, width: 720, height: 280, zone: "America/Chicago")
check("a click lands on the whole degree under it", clicked.longitude == -50 && clicked.latitude == 42, clicked)
check("a click off the edge stays on the map", WorldMap.place(x: -5, y: 999, width: 720, height: 280, zone: "z").latitude == -60, "edge")
let round = WorldMap.spot(latitude: 42, longitude: -88)
let back = WorldMap.place(x: round.x * 720, y: round.y * 280, width: 720, height: 280, zone: "z")
check("a place's dot sits where clicking it gives the same place", back.latitude == 42 && back.longitude == -88, back)
check("the land outline parsed: every landmass has corners, on the map", WorldMap.land.count > 50 && WorldMap.land.allSatisfy { $0.count >= 3 && $0.allSatisfy { abs($0.lon) <= 180 && $0.lat >= WorldMap.south && $0.lat <= WorldMap.north } }, WorldMap.land.count)
let oldConfig = try! JSONDecoder().decode(RoomLight.Place.self, from: Data(#"{"latitude":30,"longitude":-98,"zone":"America/Chicago"}"#.utf8))
check("a place is stored in whole degrees", oldConfig.latitude == 30, oldConfig)

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

if ! swiftc -o "$work/room" src/control/RoomLight.swift src/control/WorldMap.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ room-light: the harness didn't compile. RoomLight's API probably changed; update tests/drive/room-light.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/room" > "$work/out"; then
    echo "✗ room-light: Auto decided wrongly. Fix it in src/control/RoomLight.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
echo "✓ room-light: before sunset brightness is your level times the square root of the room, fitted to the day's drags, a set level keeps, contrast is a multiple of brightness you can set, after sunset the clock takes both to the night pair by bedtime, only a lit daytime drag saves the day's level, a contrast drag at brightness 0 leaves the multiple alone, Night Shift matches the fitted presets and follows Chicago's sun, it lands in ~20s, and a passing hand is ignored"
