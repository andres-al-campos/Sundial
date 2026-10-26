import Foundation

/// The decisions Auto mode makes, kept free of the sensor, the monitor and the
/// UI so they can be checked with plain numbers (`tests/drive/room-light.sh`).
///
/// One number is yours, the level: how bright you like the screen. The room's
/// light multiplies it, contrast follows brightness, and Night Shift follows the
/// clock. None of it needs presets.
enum RoomLight {
    // MARK: - Brightness

    /// The room's light that the level is stated at: at 100 lux, brightness is
    /// the level itself.
    static let referenceLux = 100.0
    /// How strongly the room moves brightness. 0.5 is a square root: sixteen
    /// times the light gives four times the brightness, as eyes compress light.
    /// With level 18 (the Morning preset's 42 at the ~550 lux measured in the
    /// lit room on 2026-10-26) a dark room at night gives ~1, where the Night
    /// presets sat.
    static let exponent = 0.5
    /// Below this the room counts as this dark, so a covered sensor's 0 lux
    /// doesn't zero the screen and a level can still be set in the dark.
    static let floorLux = 1.0

    static let defaultLevel = 18.0

    static func factor(lux: Double) -> Double {
        pow(max(lux, floorLux) / referenceLux, exponent)
    }

    static func brightness(level: Double, lux: Double) -> Double {
        clamp(level * factor(lux: lux))
    }

    /// The level that gives `brightness` in this room: what a drag of the
    /// Brightness slider saves, so the choice carries to every other room.
    static func level(forBrightness brightness: Double, lux: Double) -> Double {
        brightness / factor(lux: lux)
    }

    // MARK: - Contrast

    /// Contrast follows brightness on the line fitted to the six presets of
    /// 2026-10-26 (R² 0.82): 0/7 at midnight up to 42/69 in the morning.
    static func contrast(brightness: Double) -> Double {
        clamp(7.8 + 1.41 * brightness)
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

    /// Where the room sits on the popup's meter, 0 to 1, from 5 lux to 500 on a
    /// log scale. For showing only; brightness uses `factor`.
    static func meterPosition(lux: Double) -> Double {
        let lo = log(6.0), hi = log(501.0)
        return min(max((log(max(lux, 0) + 1) - lo) / (hi - lo), 0), 1)
    }

    /// Averages the sensor so the monitor follows the room, not the reading: a
    /// hand passing the notch swung it 30 → 600 lux within a second, and shutting
    /// the blinds took it 237 → 35 in eight. Works on log lux, so a halving of
    /// the light moves it the same at any level.
    struct Smoother {
        /// Seconds for the average to cover ~63% of a step change.
        var timeConstant: Double = 15
        private(set) var logLux: Double?

        init(timeConstant: Double = 15) { self.timeConstant = timeConstant }

        var lux: Double? { logLux.map { exp($0) - 1 } }

        /// Feed one reading taken `dt` seconds after the last. The first reading
        /// is taken as is, so Auto starts from the room it finds.
        mutating func add(lux: Double, dt: Double) -> Double {
            let x = log(max(lux, 0) + 1)
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
