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
        /// Off is a dark moment the bulb fades through. Disabled is as if the keyframe
        /// weren't there, keeping its settings for when it's enabled again.
        var enabled = true
        var brightness: Double
        var x: Double
        var y: Double

        var xy: LampBlend.XY {
            get { .init(x: x, y: y) }
            set { x = newValue.x; y = newValue.y }
        }
    }

    /// What's wrong with a set of days handed in from outside the app, in words
    /// that say how to fix it, or nil if they can be used.
    static func problem(in bulbs: [Bulb], knownIDs: Set<String>) -> String? {
        let ids = Set(bulbs.map(\.id))
        if let stray = ids.subtracting(knownIDs).first {
            return "There's no bulb \(stray) on the bridge. Use the ids from `sundial lights`."
        }
        for bulb in bulbs {
            if let parent = bulb.parent {
                guard parent != bulb.id, let p = bulbs.first(where: { $0.id == parent }) else {
                    return "\(bulb.name) follows a bulb that isn't in the file. Fix its parent, or remove it."
                }
                if p.parent != nil { return "\(bulb.name) follows \(p.name), which follows another bulb. Point it at the bulb that has the keyframes." }
            }
            for key in bulb.keys {
                guard (0..<day).contains(key.minute) else { return "\(bulb.name) has a keyframe at minute \(key.minute). Use 0 to \(day - 1)." }
                guard (0...100).contains(key.brightness) else { return "\(bulb.name) has a keyframe at brightness \(key.brightness). Use 0 to 100." }
                guard (0...1).contains(key.x), (0...1).contains(key.y) else { return "\(bulb.name) has a keyframe at xy \(key.x), \(key.y). Use 0 to 1 for both." }
            }
        }
        return nil
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

    /// What following the day does to a lamp this tick.
    enum Send: Equatable { case leave, adjust, power }

    /// A lamp that's off stays off and untouched, unless it was the day that
    /// turned it off: someone switched it off, and only they switch it back on.
    static func send(targetOn: Bool, lampIsOn: Bool, dayTurnedItOff: Bool) -> Send {
        switch (targetOn, lampIsOn) {
        case (true, true): return .adjust
        case (true, false): return dayTurnedItOff ? .power : .leave
        case (false, true): return .power
        case (false, false): return .leave
        }
    }

    static func minute(of key: Key, marks: Marks) -> Int {
        guard let a = key.anchor else { return key.minute }
        return wrap(marks.minute(of: a.mark) + a.offset)
    }

    static func wrap(_ minute: Int) -> Int { ((minute % day) + day) % day }

    /// A minute of the day as the clock reads it, for a time picker. Not midnight
    /// plus that many minutes: the days the clocks change are 23 and 25 hours long.
    static func clockTime(_ minute: Int, on date: Date, in calendar: Calendar = .current) -> Date {
        let m = wrap(minute)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: date) ?? date
    }

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

    /// The day a bulb starts with when the bridge has no scene for it: awake at sunrise,
    /// warmer by sunset, dim at bedtime. Tied to the marks, so it moves with the seasons.
    static func defaultKeys(marks: Marks) -> [Key] {
        [(Mark.sunrise, 4000.0, 100.0), (.sunset, 2700, 70), (.darkest, 2000, 15)].map { mark, kelvin, level in
            let white = LampBlend.xy(mirek: 1_000_000 / kelvin)
            return Key(minute: marks.minute(of: mark), anchor: Anchor(mark: mark, offset: 0), brightness: level, x: white.x, y: white.y)
        }
    }

    /// Whether these are still the keyframes `defaultKeys` gave, whatever the day's marks.
    static func isUntouchedDefault(_ keys: [Key]) -> Bool {
        let same: (Key) -> Key = { var k = $0; k.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!; k.minute = 0; return k }
        let start = defaultKeys(marks: Marks(sunrise: 0, sunset: 0, darkest: 0))
        return keys.map(same) == start.map(same)
    }

    /// Where a bulb should be at `minute`, leaving out one keyframe if asked:
    /// while a keyframe is dragged it shows what's under it, so it can't be part
    /// of what it's sampling. Nil for a bulb with no keyframes, which Sundial
    /// leaves alone.
    static func state(_ keys: [Key], at minute: Double, marks: Marks, without: UUID? = nil) -> State? {
        let list = keys.filter { $0.enabled && ($0.id != without || keys.count == 1) }
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

    /// Centers for labels along a line: each on its spot, moved just enough to keep
    /// `gap` between neighbours and stay on the line. Same order as given.
    static func spread(_ spots: [Double], widths: [Double], gap: Double, across length: Double) -> [Double] {
        let order = spots.indices.sorted { spots[$0] < spots[$1] }
        var centers = spots
        var edge = 0.0
        for i in order {
            centers[i] = max(spots[i], edge + widths[i] / 2)
            edge = centers[i] + widths[i] / 2 + gap
        }
        edge = length
        for i in order.reversed() {
            centers[i] = min(centers[i], edge - widths[i] / 2)
            edge = centers[i] - widths[i] / 2 - gap
        }
        return centers
    }

    // MARK: - Showing a colour

    /// The sRGB that looks closest to an xy colour at full brightness.
    static func rgb(_ xy: LampBlend.XY) -> (r: Double, g: Double, b: Double) {
        let y = max(xy.y, 0.001)
        let X = xy.x / y, Z = (1 - xy.x - xy.y) / y
        return encoded([3.2406 * X - 1.5372 - 0.4986 * Z,
                        -0.9689 * X + 1.8758 + 0.0415 * Z,
                        0.0557 * X - 0.2040 + 1.0570 * Z])
    }

    /// Brightest channel at 1, with what's out of range cut off, through the sRGB curve.
    private static func encoded(_ linear: [Double]) -> (r: Double, g: Double, b: Double) {
        let clipped = linear.map { max(0, $0) }
        let top = max(clipped.max() ?? 1, 0.001)
        let c = clipped.map { v -> Double in
            let n = v / top
            return n <= 0.0031308 ? 12.92 * n : 1.055 * pow(n, 1 / 2.4) - 0.055
        }
        return (c[0], c[1], c[2])
    }

    /// The xy of a spot on the colour wheel, its hue from 0 to 1 and its saturation
    /// from white at 0 to the full colour at 1. Its green and blue are the screen's
    /// and its red the bulbs' (Hue's gamut C). The screen's red runs out around 900 K, so
    /// on an all-sRGB wheel every temperature below that was one spot and the deepest reds
    /// were out of reach. The bulbs' green is so far past the screen's that with it a
    /// half-saturated spot showed as full green on the bands.
    static func xy(hue: Double, saturation: Double) -> LampBlend.XY {
        let h = (hue - hue.rounded(.down)) * 6, sat = min(max(0, saturation), 1)
        let t = h - h.rounded(.down)
        let full: [Double]
        switch Int(h) {
        case 0: full = [1, t, 0]
        case 1: full = [1 - t, 1, 0]
        case 2: full = [0, 1, t]
        case 3: full = [0, 1 - t, 1]
        case 4: full = [t, 0, 1]
        default: full = [1, 0, 1 - t]
        }
        let linear = full.map { v -> Double in
            let c = 1 - sat + sat * v
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let X = 0.3913 * linear[0] + 0.3762 * linear[1] + 0.1830 * linear[2]
        let Y = 0.1745 * linear[0] + 0.7523 * linear[1] + 0.0732 * linear[2]
        let Z = 0.0001 * linear[0] + 0.1254 * linear[1] + 0.9636 * linear[2]
        return .init(x: X / (X + Y + Z), y: Y / (X + Y + Z))
    }

    /// Where an xy colour sits on the colour wheel. One outside the wheel lands on
    /// the rim.
    static func wheel(_ xy: LampBlend.XY) -> (hue: Double, saturation: Double) {
        let y = max(xy.y, 0.001)
        let X = xy.x / y, Z = (1 - xy.x - xy.y) / y
        let c = encoded([3.2410 * X - 1.5374 - 0.4986 * Z,
                         -0.7612 * X + 1.7073 + 0.0149 * Z,
                         0.0987 * X - 0.2220 + 1.0359 * Z])
        let top = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b), span = top - low
        guard top > 0, span > 0 else { return (0, 0) }
        let sector: Double
        if top == c.r { sector = (c.g - c.b) / span } else if top == c.g { sector = 2 + (c.b - c.r) / span } else { sector = 4 + (c.r - c.g) / span }
        let hue = sector / 6
        return (hue - hue.rounded(.down), span / top)
    }

    /// How far a colour is dimmed on the band. The floor keeps a dim band's
    /// colour readable.
    static func shade(brightness: Double) -> Double { 0.22 + 0.78 * pow(max(0, brightness) / 100, 0.6) }

    /// The colour temperature nearest an xy, a colour's too.
    static func kelvin(_ xy: LampBlend.XY) -> Int {
        stride(from: Int(LampBlend.lowestKelvin), through: 6500, by: 50)
            .map { k -> (Int, Double) in
                let w = LampBlend.xy(mirek: 1_000_000 / Double(k))
                return (k, hypot(w.x - xy.x, w.y - xy.y))
            }
            .min { $0.1 < $1.1 }?.0 ?? 2700
    }

    /// How far off the line of glowing-metal whites a colour may sit and still have a
    /// temperature, in CIE 1960 uv.
    static let whiteTolerance = 0.02

    /// Whether a colour is a white with a temperature. The rest have a nearest number
    /// that says nothing about how they look.
    static func hasTemperature(_ xy: LampBlend.XY) -> Bool {
        offWhiteLine(xy) <= whiteTolerance
    }

    static func offWhiteLine(_ xy: LampBlend.XY) -> Double {
        func uv(_ c: LampBlend.XY) -> (u: Double, v: Double) {
            let d = -2 * c.x + 12 * c.y + 3
            return (4 * c.x / d, 6 * c.y / d)
        }
        let a = uv(xy), b = uv(LampBlend.xy(mirek: 1_000_000 / Double(kelvin(xy))))
        return hypot(a.u - b.u, a.v - b.v)
    }
}

/// A keyframe from a hand-written file needn't invent an id or say it's on.
extension LightDay.Key {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  minute: try c.decode(Int.self, forKey: .minute),
                  anchor: try c.decodeIfPresent(LightDay.Anchor.self, forKey: .anchor),
                  on: try c.decodeIfPresent(Bool.self, forKey: .on) ?? true,
                  enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
                  brightness: try c.decode(Double.self, forKey: .brightness),
                  x: try c.decode(Double.self, forKey: .x),
                  y: try c.decode(Double.self, forKey: .y))
    }
}
