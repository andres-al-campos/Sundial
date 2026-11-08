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
check("no keyframes, no state: Sundial leaves the bulb alone", LightDay.state([], at: 0, marks: m0) == nil, "state")
check("within 10 minutes snaps to a mark, across midnight too", LightDay.snap(1435, marks: m0)?.mark == .darkest && LightDay.snap(1000, marks: m0) == nil, "snap")
let ch = LightDay.choices(1149, marks: m0)
check("a keyframe can follow only the marks either side of it", ch == [.init(mark: .sunset, offset: 69), .init(mark: .darkest, offset: -291)], ch)
check("on a mark, the only choice is that mark", LightDay.choices(1080, marks: m0) == [.init(mark: .sunset, offset: 0)], LightDay.choices(1080, marks: m0))
check("a dragged keyframe near a mark lands on it", LightDay.moved(.init(mark: .sunset, offset: 60), to: 425, marks: m0, snapping: true) == .init(mark: .sunrise, offset: 0), "moved")
check("a fixed keyframe stays fixed, dragged or typed", LightDay.moved(nil, to: 500, marks: m0, snapping: true) == nil && LightDay.moved(nil, to: 425, marks: m0, snapping: false) == nil, "moved")
check("moved off its mark, an \"At Sunset\" keyframe is At This Time", LightDay.moved(.init(mark: .sunset, offset: 0), to: 1000, marks: m0, snapping: true) == nil && LightDay.moved(.init(mark: .sunset, offset: 0), to: 1000, marks: m0, snapping: false) == nil, "moved")
check("a typed time near a mark is kept as typed", LightDay.moved(.init(mark: .sunrise, offset: 30), to: 425, marks: m0, snapping: false) == .init(mark: .sunrise, offset: 5), "moved")
let pastBedtime = LightDay.moved(.init(mark: .sunset, offset: 60), to: 60, marks: m0, snapping: true)
check("moved past a mark, an after keyframe follows the mark now on its left", pastBedtime == .init(mark: .darkest, offset: 60), pastBedtime as Any)
let beforeSunrise = LightDay.moved(.init(mark: .darkest, offset: -30), to: 300, marks: m0, snapping: false)
check("a before keyframe follows the mark on its right", beforeSunrise == .init(mark: .sunrise, offset: -120), beforeSunrise as Any)
check("a pasted rule is kept at the keyframe's own time", LightDay.anchor(like: .init(mark: .sunset, offset: 60), at: 600, marks: m0, snapping: false) == .init(mark: .sunrise, offset: 180) && LightDay.anchor(like: .init(mark: .darkest, offset: -30), at: 600, marks: m0, snapping: false) == .init(mark: .sunset, offset: -480) && LightDay.anchor(like: nil, at: 600, marks: m0, snapping: false) == nil, "anchor(like:)")
check("a pasted \"At sunset\" follows the nearer mark", LightDay.anchor(like: .init(mark: .sunset, offset: 0), at: 1149, marks: m0, snapping: false) == .init(mark: .sunset, offset: 69), "anchor(like:)")
check("a new keyframe follows the nearer of its marks", LightDay.anchorForNew(1149, marks: m0) == .init(mark: .sunset, offset: 69), LightDay.anchorForNew(1149, marks: m0))
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

// An off keyframe is a dark moment the bulb fades through.
let plain = [key(8 * 60, 80), key(20 * 60, 10)]
let mNone = LightDay.Marks(sunrise: 420, sunset: 1020, darkest: 1440)
var dark = key(14 * 60, 100); dark.on = false
check("an off keyframe is still there: the bulb fades to dark at it", LightDay.state(plain + [dark], at: 14 * 60, marks: mNone)?.on == false, "off")
let wasDisabled = try! JSONDecoder().decode(LightDay.Key.self, from: Data(#"{"minute":840,"brightness":100,"x":0.4,"y":0.4,"enabled":false}"#.utf8))
check("a keyframe saved as disabled counts now that nothing can disable one", LightDay.state(plain + [wasDisabled], at: 14 * 60, marks: mNone)?.brightness == 100, wasDisabled)

// A hold ends at the next sunrise, whenever it starts.
var holdCalendar = Calendar(identifier: .gregorian)
holdCalendar.timeZone = TimeZone(identifier: "UTC")!
let holdDay = DateComponents(calendar: holdCalendar, year: 2026, month: 11, day: 4, hour: 3).date!
check("a hold before sunrise ends that morning", LightDay.holdEnd(from: holdDay, sunrise: 360, in: holdCalendar) == holdDay.addingTimeInterval(3 * 3600), "before")
let afternoon = holdDay.addingTimeInterval(12 * 3600)
check("a hold after sunrise ends the next morning", LightDay.holdEnd(from: afternoon, sunrise: 360, in: holdCalendar) == holdDay.addingTimeInterval(27 * 3600), "after")

let wanted = LightDay.State(on: true, brightness: 80, xy: .init(x: 0.4, y: 0.4))
var read = wanted
read.brightness = 80.4
check("a lamp read back rounded hasn't drifted", !LightDay.drifted(read, from: wanted), read)
read.brightness = 75
check("a lamp that lost 5% has drifted", LightDay.drifted(read, from: wanted), read)
read.on = false
check("a lamp someone switched off hasn't drifted, that's for send to judge", !LightDay.drifted(read, from: wanted), read)

// The room log's column: names kept apart from the CSV's own separators.
var logged = LightDay.Bulb(id: "x", deviceID: "dx", name: "Desk, left", keys: [])
let loggedOff = LightDay.Bulb(id: "y", deviceID: "dy", name: "Floor", keys: [])
logged.parent = nil
let line = LightDay.logged(["x": .init(on: true, brightness: 45.4, xy: .init(x: 0.5123, y: 0.4)), "y": .init(on: false, brightness: 45, xy: .init(x: 0.5, y: 0.4))], bulbs: [logged, loggedOff])
check("the room log says each bulb's look, or off", line == "Desk left=45/0.512/0.400;Floor=off", line)

// A follower is under the hold of the bulb it follows, unless it has its own.
var leader = LightDay.Bulb(id: "lead", deviceID: "d1", name: "Lead", keys: [])
var follower = LightDay.Bulb(id: "follow", deviceID: "d2", name: "Follow", keys: [])
follower.parent = leader.id
let linked = [leader, follower]
let held = LightDay.Hold(look: .init(on: true, brightness: 80, xy: .init(x: 0.4, y: 0.4)), until: afternoon)
func owner(_ id: String, _ holds: [String: LightDay.Hold]) -> String? { LightDay.holdOwner(of: id, in: linked, holds: holds) }
check("no hold, no owner", owner(follower.id, [:]) == nil, owner(follower.id, [:]) as Any)
check("a held bulb is under its own hold", owner(leader.id, [leader.id: held]) == leader.id, owner(leader.id, [leader.id: held]) as Any)
check("a follower takes the hold of the bulb it follows", owner(follower.id, [leader.id: held]) == leader.id, owner(follower.id, [leader.id: held]) as Any)
check("a follower's own hold comes first", owner(follower.id, [leader.id: held, follower.id: held]) == follower.id, owner(follower.id, [leader.id: held, follower.id: held]) as Any)
check("a hold doesn't climb from a follower to the bulb it follows", owner(leader.id, [follower.id: held]) == nil, owner(leader.id, [follower.id: held]) as Any)

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

// A new bulb's day, and whether a colour has a temperature.
let starting = LightDay.defaultKeys(marks: mNone)
check("a new bulb starts on sunrise, sunset and bedtime, following them", starting.map { $0.anchor?.mark } == [.sunrise, .sunset, .darkest] && starting.allSatisfy { $0.anchor?.offset == 0 }, starting)
check("its keyframes land on today's marks", starting.map { LightDay.minute(of: $0, marks: mNone) } == [420, 1020, 0], starting.map(\.minute))
check("and it dims into the night", starting[0].brightness > starting[1].brightness && starting[1].brightness > starting[2].brightness, starting.map(\.brightness))
check("and it starts on whites", starting.allSatisfy { LightDay.hasTemperature($0.xy) }, starting)
let otherDay = LightDay.defaultKeys(marks: LightDay.Marks(sunrise: 300, sunset: 1200, darkest: 60))
check("a day's marks don't make a new bulb's day look edited", LightDay.isUntouchedDefault(otherDay), otherDay)
var edited = starting; edited[1].brightness = 40
check("an edited one no longer counts as new", !LightDay.isUntouchedDefault(edited), edited)
var moved2 = starting; moved2[1].anchor = nil
check("nor does one taken off its mark", !LightDay.isUntouchedDefault(moved2), moved2)
check("nor one with a keyframe removed", !LightDay.isUntouchedDefault(Array(starting.dropLast())), "dropped")
for k in stride(from: 700.0, through: 6500, by: 7) {
    check("\(k) K has a temperature", LightDay.hasTemperature(LampBlend.xy(mirek: 1_000_000 / k)), k)
}
// A new keyframe takes the blend between two whites, a little off the line.
let blendA = LampBlend.xy(mirek: 500), blendB = LampBlend.xy(mirek: 250)
check("a blend of two nearby whites still has one", LightDay.hasTemperature(.init(x: (blendA.x + blendB.x) / 2, y: (blendA.y + blendB.y) / 2)), "blend")
for (name, hue) in [("green", 0.33), ("cyan", 0.5), ("blue", 0.66), ("magenta", 0.83)] {
    check("full \(name) has no temperature", !LightDay.hasTemperature(LightDay.xy(hue: hue, saturation: 1)), name)
}
check("the wheel's centre has one", LightDay.hasTemperature(LightDay.xy(hue: 0, saturation: 0)), "centre")

// The Temperature slider stays put while the wheel moves through colours.
let warmWhite = LampBlend.xy(mirek: 1_000_000 / 2700.0)
let green = LightDay.xy(hue: 0.33, saturation: 1), blue = LightDay.xy(hue: 0.66, saturation: 1)
let kept1 = LightDay.keptKelvin(leaving: warmWhite, kept: nil)
check("leaving a white keeps its temperature", kept1 == 2700, kept1)
check("the slider stays there on a colour", LightDay.sliderKelvin(green, kept: kept1) == 2700, LightDay.sliderKelvin(green, kept: kept1))
let kept2 = LightDay.keptKelvin(leaving: green, kept: kept1)
check("and through the next colour", kept2 == 2700 && LightDay.sliderKelvin(blue, kept: kept2) == 2700, kept2)
check("back on a white it shows that white's", LightDay.sliderKelvin(LampBlend.xy(mirek: 250), kept: kept2) == 4000, LightDay.sliderKelvin(LampBlend.xy(mirek: 250), kept: kept2))
check("leaving that white keeps the new one", LightDay.keptKelvin(leaving: LampBlend.xy(mirek: 250), kept: kept2) == 4000, "new")
let colourFirst = LightDay.keptKelvin(leaving: green, kept: nil)
check("a keyframe already a colour keeps what it showed", colourFirst == LightDay.sliderKelvin(green, kept: nil), colourFirst)

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
if grep -q 'ViewThatFits(' src/views/LightsView.swift || ! grep -q 'rowsFit(bulbs.count, in: geo.size.height - Layout.cardRoom)' src/views/LightsView.swift; then
    echo "✗ lamps: LightsView has to settle whether the rows scroll from the room they'd have with the card out, with no ViewThatFits. A ViewThatFits made the card jump open instead of sliding, and a scroll view resized by the slide shows a scroll bar from each frame's rounding. Pass Layout.rowsFit the height minus Layout.cardRoom, in lightsAndCard."
    exit 1
fi
if ! grep -q 'let show = shown ?? lastShown' src/views/LightsView.swift || ! grep -q '{ cardOpen = true }' src/views/LightsView.swift; then
    echo "✗ lamps: the card has to show its keyframe before it moves, and have contents before its first open. Created on that open they jump open or fade in, and changed in the same step as the slide its text and sliders travel across each other. Keep LookPanel in the card from the start showing shown ?? lastShown, and open it by animating cardOpen a frame after the selection, in LightsView.slideCard."
    exit 1
fi
if ! grep -q 'days\[l.id\] ?? LightDay.defaultKeys' src/control/LampController.swift; then
    echo "✗ lamps: a new bulb no longer gets LightDay.defaultKeys, so it has no keyframes and Sundial leaves it alone. Use them for a bulb with no scene, in LampController.syncBulbs."
    exit 1
fi
echo "✓ lamps: scenes blend in brightness and xy between keyframes, wrap midnight, the night scene holds until 30 minutes before Morning, whites convert to xy, and the scenes sit on the sun and Night Shift's ramp, DuskLight at bedtime; importing them into per-bulb keyframes keeps every minute the same, time pickers read the clock on the days it changes, a new bulb starts on sunrise, sunset and bedtime, and only whites have a temperature, with the slider staying put through colours"
