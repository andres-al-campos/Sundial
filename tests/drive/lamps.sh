#!/bin/bash
# Drive: where the lamps should be at a time of day.
#
# Compiles the app's LampBlend with a harness and feeds it keyframes shaped
# like the scenes on the bridge on 2026-10-28 (Evening, Night, MidNight,
# DuskLight, Morning), so it runs without a bridge. It can't see whether the
# bridge takes the values or how the fade looks; dev/features/lamps.md says
# how to check those.

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
typealias L = LampBlend.LampState
func lamp(_ b: Double, _ x: Double, _ y: Double) -> L { L(brightness: b, xy: .init(x: x, y: y)) }

let frames = [
    LampBlend.Keyframe(minute: 7 * 60, name: "Morning", lamps: ["1": lamp(42, 0.545, 0.418)], holds: true),
    LampBlend.Keyframe(minute: 18 * 60, name: "Evening", lamps: ["1": lamp(52, 0.523, 0.409), "2": lamp(69, 0.523, 0.409)]),
    LampBlend.Keyframe(minute: 22 * 60, name: "Night", lamps: ["1": lamp(33, 0.563, 0.400), "2": lamp(51, 0.563, 0.400)]),
    LampBlend.Keyframe(minute: 0, name: "MidNight", lamps: ["1": lamp(20, 0.602, 0.376), "2": lamp(21, 0.602, 0.376)]),
    LampBlend.Keyframe(minute: 60, name: "DuskLight", lamps: ["1": lamp(0, 0.620, 0.362), "2": lamp(0, 0.620, 0.362)], holds: true),
]
func at(_ h: Int, _ m: Int = 0) -> [String: L] { LampBlend.blend(frames, at: h * 60 + m) }

check("on a keyframe, the lamps are that scene", at(22)["1"] == frames[2].lamps["1"], at(22)["1"] as Any)
let mid = at(20)["1"]!
check("halfway from Evening to Night, brightness is halfway", near(mid.brightness, 42.5, 0.01), mid.brightness)
check("and colour is halfway along the straight line in xy", near(mid.xy.x, 0.543, 0.001) && near(mid.xy.y, 0.4045, 0.001), mid.xy)
check("each lamp keeps its own brightness", near(at(20)["2"]!.brightness, 60, 0.01), at(20)["2"]!.brightness)
check("the blend wraps midnight (23:30 is three quarters to MidNight)", near(at(23, 30)["1"]!.brightness, 23.25, 0.01), at(23, 30)["1"]!.brightness)
check("DuskLight holds through the night", at(4)["1"] == frames[4].lamps["1"], at(4)["1"] as Any)
check("and blends to Morning only in the last 30 minutes", at(6, 30)["1"] == frames[4].lamps["1"] && near(at(6, 45)["1"]!.brightness, 21, 0.01), at(6, 45)["1"]!.brightness)
check("a lamp missing from one scene takes the other's value", near(at(12)["2"]!.brightness, 69, 0.01), at(12)["2"]!.brightness)

let warm = LampBlend.xy(mirek: 500), cool = LampBlend.xy(mirek: 156)
check("2000 K is a warm white", near(warm.x, 0.527, 0.01) && near(warm.y, 0.413, 0.01), warm)
check("6400 K is a cool white", near(cool.x, 0.313, 0.01) && near(cool.y, 0.324, 0.01), cool)

let warmSched = RoomLight.WarmSchedule(from: 17 * 60 + 13, full: 24 * 60, off: 6 * 60 + 30)
let times = LampBlend.defaultTimes(warm: warmSched, sun: RoomLight.SunTimes(sunrise: 7 * 60 + 16, sunset: 17 * 60 + 53))
func t(_ n: String) -> Int { times.first { $0.name == n }!.minute }
check("Twilight is where Night Shift starts warming", t("Twilight") == warmSched.from, t("Twilight"))
check("Evening is last light, 30 minutes after sunset", t("Evening") == 18 * 60 + 23, t("Evening"))
check("DuskLight, the dimmest, is the bedtime, where Night Shift is full", t("DuskLight") == 0, t("DuskLight"))
check("MidNight an hour before, Night two", t("MidNight") == 23 * 60 && t("Night") == 22 * 60, (t("MidNight"), t("Night")))
let late = LampBlend.defaultTimes(warm: RoomLight.warmSchedule(sun: nil, bedtime: 60), sun: nil)
check("a 1:00 bedtime moves the night scenes with it", late.first { $0.name == "DuskLight" }!.minute == 60 && late.first { $0.name == "Night" }!.minute == 23 * 60, late)
check("Morning is sunrise", t("Morning") == 7 * 60 + 16, t("Morning"))

// The Lights window's day: importing the scenes must not change what the lamps do.
let scenes = Dictionary(uniqueKeysWithValues: frames.map { ($0.name, $0.lamps) })
let sceneTimes = LampBlend.defaultTimes(warm: warmSched, sun: RoomLight.SunTimes(sunrise: 7 * 60 + 16, sunset: 17 * 60 + 53))
let marks = LightDay.Marks(warm: warmSched, sun: RoomLight.SunTimes(sunrise: 7 * 60 + 16, sunset: 17 * 60 + 53))
let oldFrames = sceneTimes.compactMap { t in scenes[t.name].map { LampBlend.Keyframe(minute: t.minute, name: t.name, lamps: $0, holds: t.holds) } }
let days = LightDay.imported(scenes: scenes, times: sceneTimes, marks: marks)
var worst = 0.0
for minute in 0..<LightDay.day {
    guard let want = LampBlend.blend(oldFrames, at: minute)["1"], let got = LightDay.state(days["1"] ?? [], at: Double(minute), marks: marks) else { continue }
    worst = max(worst, abs(want.brightness - got.brightness) / 100, abs(want.xy.x - got.xy.x), abs(want.xy.y - got.xy.y))
}
check("importing the scenes reproduces the old blend at every minute", worst < 0.001, worst)
let moved = LightDay.Marks(sunrise: 5 * 60 + 30, sunset: 20 * 60 + 30, darkest: 0)
let order = (days["1"] ?? []).map { LightDay.minute(of: $0, marks: moved) }
check("a hold's end moves with the sun, so it can't pass the keyframe it leads to", (days["1"] ?? []).contains { $0.anchor?.mark == .sunrise && $0.anchor?.offset == -30 }, order)

func key(_ m: Int, _ b: Double, on: Bool = true, _ a: LightDay.Anchor? = nil) -> LightDay.Key { .init(minute: m, anchor: a, on: on, brightness: b, x: 0.5, y: 0.4) }
let k = [key(600, 50), key(720, 100), key(840, 0, on: false)]
let m0 = LightDay.Marks(sunrise: 420, sunset: 1080, darkest: 0)
check("a keyframe's line runs straight to the next", near(LightDay.state(k, at: 660, marks: m0)!.brightness, 75, 0.01), LightDay.state(k, at: 660, marks: m0) as Any)
check("fading to an off keyframe goes through dimming", near(LightDay.state(k, at: 780, marks: m0)!.brightness, 50, 0.01) && LightDay.state(k, at: 780, marks: m0)!.on, LightDay.state(k, at: 780, marks: m0) as Any)
check("the bulb is off on and after an off keyframe with nothing lit ahead", !LightDay.state(k, at: 840, marks: m0)!.on, LightDay.state(k, at: 840, marks: m0) as Any)
check("a dragged keyframe is left out of what it samples", near(LightDay.state(k, at: 720, marks: m0, without: k[1].id)!.brightness, 25, 0.01), LightDay.state(k, at: 720, marks: m0, without: k[1].id) as Any)
check("no keyframes, no state: Sundial leaves the bulb alone", LightDay.state([], at: 0, marks: m0) == nil, "state")
check("within 10 minutes snaps to a mark, across midnight too", LightDay.snap(1435, marks: m0)?.mark == .darkest && LightDay.snap(1000, marks: m0) == nil, "snap")
check("an anchored keyframe follows its mark", LightDay.minute(of: key(0, 1, .init(mark: .sunset, offset: -40)), marks: m0) == 1040, "anchor")
check("whites read back as their temperature, and a colour as the nearest one", LightDay.kelvin(LampBlend.xy(mirek: 500)) == 2000 && (700...6500).contains(LightDay.kelvin(.init(x: 0.17, y: 0.7))), "kelvin")

func bulb(_ keys: [LightDay.Key], parent: String? = nil, id: String = "1") -> LightDay.Bulb { .init(id: id, deviceID: "d", name: "Lamp", keys: keys, parent: parent) }
check("a good file is accepted", LightDay.problem(in: [bulb([key(600, 50)])], knownIDs: ["1"]) == nil, "problem")
check("a bulb that isn't on the bridge is refused", LightDay.problem(in: [bulb([], id: "9")], knownIDs: ["1"]) != nil, "problem")
check("a minute past the day is refused", LightDay.problem(in: [bulb([key(1440, 50)])], knownIDs: ["1"]) != nil, "problem")
check("brightness past 100 is refused", LightDay.problem(in: [bulb([key(600, 150)])], knownIDs: ["1"]) != nil, "problem")
check("following a missing bulb is refused", LightDay.problem(in: [bulb([], parent: "2")], knownIDs: ["1"]) != nil, "problem")
let handWritten = try! JSONDecoder().decode(LightDay.Key.self, from: Data(#"{"minute":60,"brightness":10,"x":0.5,"y":0.4}"#.utf8))
check("a hand-written keyframe needs no id and is on", handWritten.on && handWritten.minute == 60, handWritten)

let lowest = LampBlend.xy(mirek: 1_000_000 / LampBlend.lowestKelvin)
check("the lowest white is the bulbs' red corner, or a lower one would look the same", near(lowest.x, 0.692, 0.005) && near(lowest.y, 0.308, 0.005), lowest)
let below = LampBlend.xy(mirek: 1_000_000 / 1666), above = LampBlend.xy(mirek: 1_000_000 / 1668)
check("the slider doesn't jump where the low table meets the fit at 1667 K", near(below.x, above.x, 0.002) && near(below.y, above.y, 0.002), (below, above))
check("1000 K is the published CIE point", near(LampBlend.xy(mirek: 1000).x, 0.6528, 0.0005) && near(LampBlend.xy(mirek: 1000).y, 0.3445, 0.0005), LampBlend.xy(mirek: 1000))
for hue in stride(from: 0.0, to: 1.0, by: 0.05) {
    for saturation in [0.25, 0.6, 1.0] {
        let spot = LightDay.wheel(LightDay.xy(hue: hue, saturation: saturation))
        check("the colour wheel gives back the spot that was picked, or its thumb jumps under the pointer", near(spot.hue, hue, 0.01) && near(spot.saturation, saturation, 0.01), (hue, saturation, spot))
    }
}
check("the centre of the colour wheel is white", near(LightDay.xy(hue: 0.3, saturation: 0).x, 0.3127, 0.001) && near(LightDay.xy(hue: 0.3, saturation: 0).y, 0.329, 0.001), LightDay.xy(hue: 0.3, saturation: 0))
check("a wheel drag past the rim stays on the rim", LightDay.xy(hue: 0.2, saturation: 3) == LightDay.xy(hue: 0.2, saturation: 1), "")
check("the wheel's red is the bulbs' red, not the screen's, or the deepest reds are out of reach", near(LightDay.xy(hue: 0, saturation: 1).x, 0.6915, 0.002) && near(LightDay.xy(hue: 0, saturation: 1).y, 0.3083, 0.002), LightDay.xy(hue: 0, saturation: 1))
func spot(_ k: Double) -> (x: Double, y: Double) {
    let w = LightDay.wheel(LampBlend.xy(mirek: 1_000_000 / k))
    return (cos(w.hue * 2 * .pi) * w.saturation, sin(w.hue * 2 * .pi) * w.saturation)
}
for k in stride(from: 700.0, to: 2500, by: 100) {
    let a = spot(k), b = spot(k + 100)
    check("the wheel's thumb moves as Temperature goes from \(Int(k)) to \(Int(k) + 100) K, or it reads as stuck", hypot(a.x - b.x, a.y - b.y) > 0.02, (a, b))
}
check("MidNight's colour reads as a temperature, so its slider doesn't jump", (1000...1700).contains(LightDay.kelvin(.init(x: 0.602, y: 0.376))), LightDay.kelvin(.init(x: 0.602, y: 0.376)))
check("a lamp someone switched off stays off", LightDay.send(targetOn: true, lampIsOn: false, dayTurnedItOff: false) == .leave, "send")
check("a lamp the day turned off comes back with the day", LightDay.send(targetOn: true, lampIsOn: false, dayTurnedItOff: true) == .power, "send")
check("a lit lamp is adjusted without touching its power", LightDay.send(targetOn: true, lampIsOn: true, dayTurnedItOff: false) == .adjust, "send")
check("the day can still turn a lit lamp off", LightDay.send(targetOn: false, lampIsOn: true, dayTurnedItOff: false) == .power, "send")
check("nothing is sent to a lamp already off when the day says off", LightDay.send(targetOn: false, lampIsOn: false, dayTurnedItOff: true) == .leave, "send")

func clear(_ centers: [Double], _ widths: [Double], gap: Double, across: Double) -> Bool {
    let spans = zip(centers, widths).map { (l: $0 - $1 / 2, r: $0 + $1 / 2) }.sorted { $0.l < $1.l }
    return spans.first!.l >= -0.001 && spans.last!.r <= across + 0.001 && zip(spans, spans.dropFirst()).allSatisfy { $0.r + gap <= $1.l + 0.001 }
}
let w = [90.0, 90.0, 90.0]
check("labels far apart stay on their marks", LightDay.spread([100, 300, 500], widths: w, gap: 8, across: 600) == [100, 300, 500], "spread")
for spots in [[300.0, 310, 320], [320, 300, 310], [0, 5, 10], [590, 595, 600], [10, 300, 595]] {
    let got = LightDay.spread(spots, widths: w, gap: 8, across: 600)
    check("labels at \(spots) don't overlap or leave the row", clear(got, w, gap: 8, across: 600), got)
}
let crossed = LightDay.spread([320, 300], widths: [90, 90], gap: 8, across: 600)
check("labels pushed apart keep their order", crossed[1] < crossed[0], crossed)

// A disabled keyframe is as if it weren't there, unlike an off one.
let plain = [key(8 * 60, 80), key(20 * 60, 10)]
var extra = key(14 * 60, 100); extra.enabled = false
let mNone = LightDay.Marks(sunrise: 420, sunset: 1020, darkest: 1440)
let sameDay = (0..<LightDay.day).allSatisfy { LightDay.state(plain + [extra], at: Double($0), marks: mNone) == LightDay.state(plain, at: Double($0), marks: mNone) }
check("a disabled keyframe leaves the day as if it weren't there", sameDay, "disabled")
var dark = extra; dark.enabled = true; dark.on = false
check("an off keyframe is still there: the bulb fades to dark at it", LightDay.state(plain + [dark], at: 14 * 60, marks: mNone)?.on == false, "off")
check("a bulb with only disabled keyframes is left alone", LightDay.state([extra], at: 0, marks: mNone) == nil, "alone")
let oldKey = try! JSONDecoder().decode(LightDay.Key.self, from: Data(#"{"minute":60,"brightness":50,"x":0.4,"y":0.4}"#.utf8))
check("a keyframe saved before disabling existed is enabled", oldKey.enabled, oldKey)
var kept = extra; kept.enabled = false
let roundTrip = try! JSONDecoder().decode(LightDay.Key.self, from: JSONEncoder().encode(kept))
check("disabled survives saving", roundTrip.enabled == false, roundTrip)

// A time picker reads the clock, on the 25-hour and 23-hour days too.
var chicago = Calendar(identifier: .gregorian)
chicago.timeZone = TimeZone(identifier: "America/Chicago")!
func read(_ d: Date) -> Int {
    let c = chicago.dateComponents([.hour, .minute], from: d)
    return c.hour! * 60 + c.minute!
}
let clockDays = ["fall back": DateComponents(year: 2026, month: 11, day: 1, hour: 22),
            "spring forward": DateComponents(year: 2027, month: 3, day: 14, hour: 22),
            "an ordinary day": DateComponents(year: 2026, month: 11, day: 2, hour: 22)]
for (name, parts) in clockDays {
    let date = chicago.date(from: parts)!
    for minute in [0, 60, 4 * 60, 17 * 60 + 42, 23 * 60 + 59] {
        let got = LightDay.clockTime(minute, on: date, in: chicago)
        check("minute \(minute) reads the same on \(name)", read(got) == minute, read(got))
        check("and stays on that day on \(name)", chicago.isDate(got, inSameDayAs: date), got)
    }
}
check("24:00 bedtime reads as midnight", read(LightDay.clockTime(24 * 60, on: chicago.date(from: clockDays["fall back"]!)!, in: chicago)) == 0, "bedtime")

if !failures.isEmpty {
    failures.forEach { print("    \($0)") }
    exit(1)
}
SWIFT

if ! swiftc -o "$work/lamps" src/control/RoomLight.swift src/control/LampBlend.swift src/control/LightDay.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ lamps: the harness didn't compile. LampBlend's API probably changed; update tests/drive/lamps.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/lamps" > "$work/out"; then
    echo "✗ lamps: the lamps would be set wrongly. Fix it in src/control/LampBlend.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
echo "✓ lamps: scenes blend in brightness and xy between keyframes, wrap midnight, the night scene holds until 30 minutes before Morning, whites convert to xy, and the scenes sit on the sun and Night Shift's ramp, DuskLight at bedtime; importing them into per-bulb keyframes keeps every minute the same, and time pickers read the clock on the days it changes"
