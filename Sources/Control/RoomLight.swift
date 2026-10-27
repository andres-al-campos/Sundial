import Foundation

/// The decisions Auto mode makes, kept free of the sensor, the monitor and the
/// UI so they can be checked with plain numbers (`tests/drive/room-light.sh`).
///
/// One number is yours, the level: how bright you like the screen. The room's
/// light multiplies it; contrast
/// follows brightness, and Night Shift follows the clock. None of it needs
/// presets.
enum RoomLight {
    // MARK: - Brightness

    /// The room's light that the level is stated at: at 100 lux, brightness is
    /// the level itself.
    static let referenceLux = 100.0
    /// How strongly the room moves brightness. 0.25 is a fourth root: sixteen
    /// times the light gives twice the brightness. Fitted to the seven
    /// brightnesses set on the evening of 2026-10-26, from 60 at 133 lux to
    /// 17-22 at 2 lux; a square root dimmed the dark room far below them.
    static let exponent = 0.25
    /// Readings below this count as this: under about 0.1 lux the sensor reads
    /// 0, so lower isn't darker, only unmeasured.
    static let floorLux = 0.1

    /// The level those seven settings fit: 17 at 2 lux, 30 at 30, 43 at 84.
    static let defaultLevel = 45.0

    /// The room's multiplier on your level: 1 at 100 lux.
    static func factor(lux: Double) -> Double {
        pow(max(lux, floorLux) / referenceLux, exponent)
    }

    /// The monitor's darkest, brightness 0 and contrast 0, is a level of 0, in
    /// any room.
    static func brightness(level: Double, lux: Double) -> Double {
        clamp(level * factor(lux: lux))
    }

    /// The level that gives `brightness` in this room: what a drag of the
    /// Brightness slider saves, so the choice carries to every other room.
    static func level(forBrightness brightness: Double, lux: Double) -> Double {
        brightness / factor(lux: lux)
    }

    // MARK: - Contrast

    /// Contrast is a multiple of brightness, so brightness 0 is contrast 0 too,
    /// the monitor's darkest. √2 to start: the presets' own line had that slope
    /// plus 7.8. Dragging Contrast sets the multiple.
    static let defaultContrastScale = 2.0.squareRoot()

    static func contrast(brightness: Double, scale: Double = defaultContrastScale) -> Double {
        clamp(scale * brightness)
    }

    /// The multiple that gives `contrast` at `brightness`: what a drag of the
    /// Contrast slider saves. At brightness 0 every multiple gives 0, so it's
    /// worked out as if brightness were 1.
    static func contrastScale(forContrast contrast: Double, brightness: Double) -> Double {
        contrast / max(brightness, 1)
    }

    // MARK: - Night Shift

    /// When Night Shift warms, in minutes after midnight: off until `from`,
    /// rising evenly to full at `full` (past 1440 is after midnight), full until
    /// `off`, then off.
    struct WarmSchedule: Equatable {
        var from: Int
        var full: Int
        var off: Int
    }

    /// Fitted to the presets' evening values (31% at 7:17 PM, 42% at 8:07, 67%
    /// at 10:17, 100% at 11:57; R² 0.98): off until 5:13 PM, rising ~14% an hour
    /// to full at 12:11 AM, full until 6:30 AM. Used as is when the sun's times
    /// aren't known.
    static let fittedSchedule = WarmSchedule(from: 17 * 60 + 13, full: 24 * 60 + 11, off: 6 * 60 + 30)
    /// The fitted times against Chicago's sun on the day they were fitted
    /// (2026-10-26, sunset 5:53 PM, sunrise 7:16 AM): warming starts 40
    /// minutes before sunset and ends 46 minutes before sunrise. Full stays at
    /// 12:11 AM, a bedtime, which the sun doesn't move.
    static let warmBeforeSunset = 40.0
    static let offBeforeSunrise = 46.0

    /// The fitted schedule moved with the season: start and end follow the sun.
    static func warmSchedule(sun: SunTimes?) -> WarmSchedule {
        guard let sun else { return fittedSchedule }
        return WarmSchedule(from: Int((sun.sunset - warmBeforeSunset).rounded()),
                            full: fittedSchedule.full,
                            off: Int((sun.sunrise - offBeforeSunrise).rounded()))
    }

    static func nightShift(minuteOfDay m: Int, schedule: WarmSchedule = fittedSchedule) -> Double {
        // Minutes since the ramp began, counting past midnight.
        let since = (m - schedule.from + 24 * 60) % (24 * 60)
        let ramp = schedule.full - schedule.from
        let offAfter = (schedule.off - schedule.from + 24 * 60) % (24 * 60)
        if since <= ramp { return 100 * Double(since) / Double(ramp) }
        if since < offAfter { return 100 }
        return 0
    }

    // MARK: - The sun

    /// Sunrise and sunset in minutes after local midnight.
    struct SunTimes: Equatable {
        var sunrise: Double
        var sunset: Double
    }

    /// Sunrise and sunset on a day at a place, by NOAA's solar formulas (within
    /// a minute or two of their tables). `utcOffset` is the place's offset from
    /// UTC in hours on that day; longitude is east-positive. Nil where the sun
    /// doesn't rise or set that day.
    static func sunTimes(year: Int, month: Int, day: Int, latitude: Double, longitude: Double, utcOffset: Double) -> SunTimes? {
        let rad = Double.pi / 180
        let a = (14 - month) / 12, y = year + 4800 - a, mo = month + 12 * a - 3
        let jdn = day + (153 * mo + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        // Local noon, in Julian centuries since 2000.
        let t = (Double(jdn) - utcOffset / 24 - 2_451_545) / 36525
        let l = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t) + sin(3 * m * rad) * 0.000289
        let omega = (125.04 - 1934.136 * t) * rad
        let lambda = l + c - 0.00569 - 0.00478 * sin(omega)
        let eps = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60 + 0.00256 * cos(omega)
        let decl = asin(sin(eps * rad) * sin(lambda * rad))
        let yv = pow(tan(eps * rad / 2), 2)
        let eqTime = 4 / rad * (yv * sin(2 * l * rad) - 2 * e * sin(m * rad)
            + 4 * e * yv * sin(m * rad) * cos(2 * l * rad)
            - 0.5 * yv * yv * sin(4 * l * rad) - 1.25 * e * e * sin(2 * m * rad))
        let cosHA = cos(90.833 * rad) / (cos(latitude * rad) * cos(decl)) - tan(latitude * rad) * tan(decl)
        guard abs(cosHA) <= 1 else { return nil }
        let ha = acos(cosHA) / rad
        let noon = 720 - 4 * longitude - eqTime + utcOffset * 60
        return SunTimes(sunrise: noon - 4 * ha, sunset: noon + 4 * ha)
    }

    /// A place from the time zone table (`zone.tab`): "+415100-0873900" is
    /// 41°51'00" N, 87°39'00" W. Nil when it doesn't parse.
    static func coordinates(iso6709 text: String) -> (latitude: Double, longitude: Double)? {
        let chars = Array(text)
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        func parse(_ part: ArraySlice<Character>, degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = Array(part.dropFirst())
            guard digits.count >= degreeDigits + 2, digits.allSatisfy(\.isNumber) else { return nil }
            let d = Double(String(digits[0..<degreeDigits]))!
            let mi = Double(String(digits[degreeDigits..<degreeDigits + 2]))!
            let se = digits.count >= degreeDigits + 4 ? Double(String(digits[degreeDigits + 2..<degreeDigits + 4]))! : 0
            return (sign == "-" ? -1 : 1) * (d + mi / 60 + se / 3600)
        }
        guard let lat = parse(chars[..<split], degreeDigits: 2),
              let lon = parse(chars[split...], degreeDigits: 3) else { return nil }
        return (lat, lon)
    }

    // MARK: - The room

    /// Where the room sits on the popup's meter, 0 to 1, from 0.1 lux to 1000
    /// on a log scale, so the dark steps the sensor can tell apart show. For
    /// showing only; brightness uses `factor`.
    static func meterPosition(lux: Double) -> Double {
        let lo = log10(0.1), hi = log10(1000.0)
        return min(max((log10(max(lux, 0.1)) - lo) / (hi - lo), 0), 1)
    }

    /// Averages the sensor so the monitor follows the room, not the reading.
    /// A median of the last 5 seconds first drops a hand passing the notch
    /// (30 → 600 lux and back within a second); a short average then smooths
    /// what's left, so shutting the blinds (237 → 35 lux in eight seconds) or a
    /// cloud lands in about 20 seconds. Big changes are meant to be seen; most
    /// are small. Works on log lux, so a halving of the light moves it the same
    /// at any level.
    struct Smoother {
        /// Seconds for the average to cover ~63% of a step change.
        var timeConstant: Double = 6
        /// Readings the median is taken over, one a second.
        var medianWindow = 5
        private(set) var logLux: Double?
        private var recent: [Double] = []

        init(timeConstant: Double = 6, medianWindow: Int = 5) {
            self.timeConstant = timeConstant
            self.medianWindow = medianWindow
        }

        var lux: Double? { logLux.map { exp($0) - 1 } }

        /// Feed one reading taken `dt` seconds after the last. The first reading
        /// is taken as is, so Auto starts from the room it finds.
        mutating func add(lux: Double, dt: Double) -> Double {
            recent.append(max(lux, 0))
            if recent.count > medianWindow { recent.removeFirst() }
            let median = recent.sorted()[recent.count / 2]
            let x = log(median + 1)
            if let current = logLux {
                let alpha = 1 - exp(-dt / timeConstant)
                logLux = current + alpha * (x - current)
            } else {
                logLux = x
            }
            return exp(logLux!) - 1
        }
    }

    /// Moves `value` toward `target` by at most `maxStep`. The monitor eases to
    /// a new target instead of jumping, whatever moved the target.
    static func step(_ value: Double, toward target: Double, maxStep: Double) -> Double {
        let d = target - value
        return abs(d) <= maxStep ? target : value + (d > 0 ? maxStep : -maxStep)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 100) }
}
