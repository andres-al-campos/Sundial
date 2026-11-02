import Foundation

/// What each bulb does through the day: its own keyframes, with a straight line
/// between neighbours. There are no hidden holds, so a hold is two matching
/// keyframes and the band in the Lights window is exactly what the bulb does.
///
/// Pure, so tests/drive/lamps.sh can run it without a bridge.
enum LightDay {
    enum Mark: String, Codable, CaseIterable { case sunrise, sunset, darkest }

    /// A keyframe tied to the day's marks, which move with the seasons and with
    /// the darkest time. Scenes placed "40 minutes before sunset" keep that as
    /// sunset moves; a fixed time would drift past its neighbours by summer.
    struct Anchor: Codable, Equatable {
        var mark: Mark
        var offset: Int
    }

    struct Marks: Equatable {
        var sunrise: Int
        var sunset: Int
        var darkest: Int

        func minute(of mark: Mark) -> Int {
            switch mark {
            case .sunrise: return sunrise
            case .sunset: return sunset
            case .darkest: return darkest
            }
        }

        init(sunrise: Int, sunset: Int, darkest: Int) {
            self.sunrise = sunrise
            self.sunset = sunset
            self.darkest = darkest
        }

        init(warm: RoomLight.WarmSchedule, sun: RoomLight.SunTimes?) {
            sunrise = sun.map { Int($0.sunrise.rounded()) } ?? 7 * 60
            sunset = sun.map { Int($0.sunset.rounded()) } ?? warm.from + 40
            darkest = warm.full % day
        }
    }

    struct Key: Codable, Equatable, Identifiable {
        var id = UUID()
        var minute: Int
        var anchor: Anchor?
        /// Separate from brightness: 0 is the bulb's dimmest, and an off
        /// keyframe remembers its brightness for when it's switched back on.
        var on = true
        var brightness: Double
        var x: Double
        var y: Double

        var xy: LampBlend.XY {
            get { .init(x: x, y: y) }
            set { x = newValue.x; y = newValue.y }
        }
    }

    struct Bulb: Codable, Equatable, Identifiable {
        var id: String
        var deviceID: String
        var name: String
        var keys: [Key] = []
        /// The bulb whose day this one follows. One level only.
        var parent: String?
    }

    struct State: Equatable {
        var on: Bool
        var brightness: Double
        var xy: LampBlend.XY
    }

    static let day = 24 * 60
    /// A keyframe this close to a mark snaps to it and follows it.
    static let snapDistance = 10

    static func minute(of key: Key, marks: Marks) -> Int {
        guard let a = key.anchor else { return key.minute }
        return wrap(marks.minute(of: a.mark) + a.offset)
    }

    static func wrap(_ minute: Int) -> Int { ((minute % day) + day) % day }

    /// The mark a time snaps to, if it's close enough to one.
    static func snap(_ minute: Int, marks: Marks) -> Anchor? {
        Mark.allCases
            .map { (mark: $0, gap: abs(signedGap(from: marks.minute(of: $0), to: minute))) }
            .filter { $0.gap <= snapDistance }
            .min { $0.gap < $1.gap }
            .map { Anchor(mark: $0.mark, offset: 0) }
    }

    /// The shortest way from one time of day to another, through midnight if
    /// that's shorter: -720 to 720.
    static func signedGap(from a: Int, to b: Int) -> Int {
        let d = wrap(b - a)
        return d > day / 2 ? d - day : d
    }

    /// The day a bulb actually follows: its own, or its parent's.
    static func keys(of bulb: Bulb, in bulbs: [Bulb]) -> [Key] {
        guard let parent = bulb.parent else { return bulb.keys }
        return bulbs.first { $0.id == parent }?.keys ?? bulb.keys
    }

    /// Where a bulb should be at `minute`, leaving out one keyframe if asked:
    /// while a keyframe is dragged it shows what's under it, so it can't be part
    /// of what it's sampling. Nil for a bulb with no keyframes, which Sundial
    /// leaves alone.
    static func state(_ keys: [Key], at minute: Double, marks: Marks, without: UUID? = nil) -> State? {
        let list = keys.filter { $0.id != without || keys.count == 1 }
            .map { (key: $0, at: Double(Self.minute(of: $0, marks: marks))) }
            .sorted { $0.at < $1.at }
        guard let first = list.first else { return nil }
        guard list.count > 1 else { return State(on: first.key.on, brightness: first.key.brightness, xy: first.key.xy) }

        let i = list.lastIndex { $0.at <= minute } ?? list.count - 1
        let a = list[i], b = list[(i + 1) % list.count]
        let total = Double(day)
        let gap = (b.at - a.at + total).truncatingRemainder(dividingBy: total)
        let t = gap == 0 ? 0 : (minute - a.at + total).truncatingRemainder(dividingBy: total) / gap

        // Fading to or from off goes through the bulb's dimming, in the lit
        // keyframe's colour.
        let from = a.key.on ? a.key : b.key, to = b.key.on ? b.key : a.key
        let fromLevel = a.key.on ? a.key.brightness : 0, toLevel = b.key.on ? b.key.brightness : 0
        return State(
            on: (a.key.on || b.key.on) && !(t == 0 && !a.key.on),
            brightness: fromLevel + (toLevel - fromLevel) * t,
            xy: .init(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        )
    }

    /// Each lamp's day from the scenes on the bridge, the once: from here on
    /// Sundial holds the settings. A scene that held turns into two matching
    /// keyframes, so the band shows the hold.
    static func imported(scenes: [String: [String: LampBlend.LampState]], times: [(name: String, minute: Int, holds: Bool)], marks: Marks) -> [String: [Key]] {
        // Which mark each scene moves with, as `LampBlend.defaultTimes` places them.
        let follows: [String: Mark] = ["Morning": .sunrise, "Twilight": .sunset, "Evening": .sunset,
                                       "Night": .darkest, "MidNight": .darkest, "DuskLight": .darkest]
        func anchor(_ name: String, _ minute: Int) -> Anchor? {
            follows[name].map { Anchor(mark: $0, offset: signedGap(from: marks.minute(of: $0), to: minute)) }
        }
        let placed = times.filter { scenes[$0.name] != nil }.sorted { $0.minute < $1.minute }
        var out: [String: [Key]] = [:]
        for (i, t) in placed.enumerated() {
            let next = placed[(i + 1) % placed.count]
            let gap = wrap(next.minute - t.minute)
            for (lamp, s) in scenes[t.name] ?? [:] {
                out[lamp, default: []].append(Key(minute: t.minute, anchor: anchor(t.name, t.minute), brightness: s.brightness, x: s.xy.x, y: s.xy.y))
                if t.holds, placed.count > 1, gap > LampBlend.settle {
                    let at = wrap(next.minute - LampBlend.settle)
                    let moved = anchor(next.name, next.minute).map { Anchor(mark: $0.mark, offset: $0.offset - LampBlend.settle) }
                    out[lamp, default: []].append(Key(minute: at, anchor: moved, brightness: s.brightness, x: s.xy.x, y: s.xy.y))
                }
            }
        }
        return out
    }

    // MARK: - Showing a colour

    /// The sRGB that looks closest to an xy colour at full brightness.
    static func rgb(_ xy: LampBlend.XY) -> (r: Double, g: Double, b: Double) {
        let y = max(xy.y, 0.001)
        let X = xy.x / y, Z = (1 - xy.x - xy.y) / y
        let linear = [3.2406 * X - 1.5372 - 0.4986 * Z,
                      -0.9689 * X + 1.8758 + 0.0415 * Z,
                      0.0557 * X - 0.2040 + 1.0570 * Z].map { max(0, $0) }
        let top = max(linear.max() ?? 1, 0.001)
        let c = linear.map { v -> Double in
            let n = v / top
            return n <= 0.0031308 ? 12.92 * n : 1.055 * pow(n, 1 / 2.4) - 0.055
        }
        return (c[0], c[1], c[2])
    }

    /// How far a colour is dimmed on the band. The floor keeps a dim band's
    /// colour readable.
    static func shade(brightness: Double) -> Double { 0.22 + 0.78 * pow(max(0, brightness) / 100, 0.6) }

    /// The colour temperature an xy is a white of, or nil for a colour.
    static func kelvin(_ xy: LampBlend.XY) -> Int? {
        let (best, gap) = stride(from: 1700, through: 6500, by: 50)
            .map { k -> (Int, Double) in
                let w = LampBlend.xy(mirek: 1_000_000 / Double(k))
                return (k, hypot(w.x - xy.x, w.y - xy.y))
            }
            .min { $0.1 < $1.1 } ?? (2700, 1)
        return gap < 0.012 ? best : nil
    }
}
