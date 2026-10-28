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
check("MidNight is the bedtime, where Night Shift is full", t("MidNight") == 0, t("MidNight"))
check("Morning is sunrise", t("Morning") == 7 * 60 + 16, t("Morning"))

if !failures.isEmpty {
    failures.forEach { print("    \($0)") }
    exit(1)
}
SWIFT

if ! swiftc -o "$work/lamps" src/control/RoomLight.swift src/control/LampBlend.swift "$work/main.swift" 2> "$work/err"; then
    echo "✗ lamps: the harness didn't compile. LampBlend's API probably changed; update tests/drive/lamps.sh to match."
    sed 's/^/    /' "$work/err"
    exit 1
fi
if ! "$work/lamps" > "$work/out"; then
    echo "✗ lamps: the lamps would be set wrongly. Fix it in src/control/LampBlend.swift, or the case here if the rule changed on purpose:"
    cat "$work/out"
    exit 1
fi
echo "✓ lamps: scenes blend in brightness and xy between keyframes, wrap midnight, the night scene holds until 30 minutes before Morning, whites convert to xy, and the scenes sit on the sun and Night Shift's ramp"
