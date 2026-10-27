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

    /// Night Shift by the clock, fitted to the presets' evening values
    /// (31% at 7:17 PM, 42% at 8:07, 67% at 10:17, 100% at 11:57; R² 0.98):
    /// off until 5:13 PM, rising ~14% an hour to full at 12:11 AM, full until
    /// 6:30 AM, then off.
    static let warmFrom = 17 * 60 + 13
    static let warmFull = 24 * 60 + 11
    static let warmOff = 6 * 60 + 30

    static func nightShift(minuteOfDay m: Int) -> Double {
        // Minutes since the ramp began, counting past midnight.
        let since = (m - warmFrom + 24 * 60) % (24 * 60)
        let ramp = warmFull - warmFrom
        let offAfter = (warmOff - warmFrom + 24 * 60) % (24 * 60)
        if since <= ramp { return 100 * Double(since) / Double(ramp) }
        if since < offAfter { return 100 }
        return 0
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
