import Foundation

/// Where the lamps should be at a time of day: the scenes are keyframes, and
/// each lamp blends between the two around now, brightness linearly and colour
/// along a straight line in CIE xy, Hue's own colour space, where a straight
/// line is what mixing the two lights looks like. A hue wheel's straight line
/// detours through colours neither scene has.
///
/// Pure, so tests/drive/lamps.sh can run it without a bridge.
enum LampBlend {
    struct XY: Equatable { var x: Double; var y: Double }
    struct LampState: Equatable { var brightness: Double; var xy: XY }

    /// A scene placed on the day: its lamps' values, keyed by lamp id.
    struct Keyframe {
        var minute: Int
        var name: String
        var lamps: [String: LampState]
        /// Hold this scene until `settle` minutes before the next, then blend.
        /// The day's scenes and the last night scene hold: blending DuskLight
        /// to Morning the whole way would brighten the lamps all night. The
        /// evening ones blend the whole way, as Night Shift does.
        var holds = false
    }

    static let settle = 30

    /// The scenes Sundial places, in day order, and when: tied to the sun
    /// where the day is, to the bedtime ramp at night. Twilight sits where
    /// Night Shift starts warming and MidNight where it's full, so the screen
    /// and the lamps are always at the same point of the evening, and
    /// DuskLight, the dimmest, at bedtime, where Night Shift is full. Night and
    /// MidNight two hours and one before bedtime are guesses until there's an
    /// editor to set them.
    static func defaultTimes(warm: RoomLight.WarmSchedule, sun: RoomLight.SunTimes?) -> [(name: String, minute: Int, holds: Bool)] {
        let sunrise = sun.map { Int($0.sunrise.rounded()) } ?? 7 * 60
        let lastLight = sun.map { Int(($0.sunset + 30).rounded()) } ?? warm.from + 70
        let bed = warm.full % (24 * 60)
        return [
            ("Morning", sunrise, true),
            ("Noon", 12 * 60, true),
            ("Twilight", warm.from, false),
            ("Evening", lastLight, false),
            ("Night", (bed - 120 + 24 * 60) % (24 * 60), false),
            ("MidNight", (bed - 60 + 24 * 60) % (24 * 60), false),
            ("DuskLight", bed, true),
        ]
    }

    /// Each lamp's state at `minute`. A lamp missing from one of the two
    /// keyframes takes the other's value.
    static func blend(_ frames: [Keyframe], at minute: Int) -> [String: LampState] {
        let day = 24 * 60
        let sorted = frames.sorted { $0.minute < $1.minute }
        guard let first = sorted.first else { return [:] }
        guard sorted.count > 1 else { return first.lamps }

        // The keyframe at or before now, and the next one, wrapping midnight.
        let i = sorted.lastIndex { $0.minute <= minute } ?? sorted.count - 1
        let a = sorted[i], b = sorted[(i + 1) % sorted.count]
        let gap = (b.minute - a.minute + day) % day
        let since = (minute - a.minute + day) % day
        let t: Double
        if gap == 0 {
            t = 0
        } else if a.holds {
            let start = max(0, gap - settle)
            t = since < start ? 0 : Double(since - start) / Double(settle)
        } else {
            t = Double(since) / Double(gap)
        }

        var out: [String: LampState] = [:]
        for id in Set(a.lamps.keys).union(b.lamps.keys) {
            guard let from = a.lamps[id] ?? b.lamps[id], let to = b.lamps[id] ?? a.lamps[id] else { continue }
            out[id] = LampState(brightness: from.brightness + (to.brightness - from.brightness) * t,
                                xy: XY(x: from.xy.x + (to.xy.x - from.xy.x) * t,
                                       y: from.xy.y + (to.xy.y - from.xy.y) * t))
        }
        return out
    }

    /// The xy of a white at this colour temperature (mirek = 1,000,000 / K),
    /// on the Planckian locus by Kim et al.'s fit, good from 1667 K to 25000 K.
    /// Scenes store whites as mirek and colours as xy; blending needs one.
    static func xy(mirek: Double) -> XY {
        let k = min(25000, max(1667, 1_000_000 / mirek))
        let x: Double = k <= 4000
            ? -0.2661239e9 / (k * k * k) - 0.2343589e6 / (k * k) + 0.8776956e3 / k + 0.179910
            : -3.0258469e9 / (k * k * k) + 2.1070379e6 / (k * k) + 0.2226347e3 / k + 0.240390
        let y: Double
        if k <= 2222 {
            y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if k <= 4000 {
            y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        }
        return XY(x: x, y: y)
    }
}
