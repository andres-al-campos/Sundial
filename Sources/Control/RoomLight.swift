import Foundation

/// The decisions Auto mode makes from the room's light, kept free of the
/// sensor, the monitor and the UI so they can be checked with plain numbers
/// (`tests/drive/room-light.sh`).
enum RoomLight {
    /// One end of Auto's range: what the monitor shows in a dark room, or in a
    /// bright one. Between them the room's light picks a point.
    struct End: Codable, Equatable {
        var brightness: Int
        var contrast: Int
    }

    /// Lux at which the room counts as fully dark and fully bright. Measured on
    /// 2026-10-26 with the MacBook's sensor: ~550 in the lit room on a clear
    /// afternoon, ~35 with the blinds shut. Below and above these the ends hold.
    static let darkLux = 5.0
    static let brightLux = 500.0

    /// Where the room sits between dark (0) and bright (1). On a log scale,
    /// because eyes judge light by ratios: 30 → 300 lux should be the same step
    /// as 300 → 3000.
    static func position(lux: Double) -> Double {
        let lo = log(darkLux + 1), hi = log(brightLux + 1)
        let t = (log(max(lux, 0) + 1) - lo) / (hi - lo)
        return min(max(t, 0), 1)
    }

    /// Brightness and contrast for a room at `position`, each a straight line
    /// between the two ends.
    static func target(position t: Double, dark: End, bright: End) -> (brightness: Double, contrast: Double) {
        (Double(dark.brightness) + t * Double(bright.brightness - dark.brightness),
         Double(dark.contrast)   + t * Double(bright.contrast   - dark.contrast))
    }

    // MARK: - Smoothing

    /// Averages the sensor so the monitor follows the room, not the reading: a
    /// hand passing the notch swung it 30 → 600 lux within a second, and shutting
    /// the blinds took it 237 → 35 in eight. Works on log lux, so a halving of
    /// the light moves it the same at any level.
    struct Smoother {
        /// Seconds for the average to cover ~63% of a step change.
        var timeConstant: Double = 45
        private(set) var logLux: Double?

        init(timeConstant: Double = 45) { self.timeConstant = timeConstant }

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

    // MARK: - Hold

    /// A brightness set by hand in Auto mode, for a dark video or the like. It
    /// holds until it lapses, then Auto eases back.
    struct Hold: Equatable {
        var brightness: Int
        var since: Date
        /// The averaged room when the hold began.
        var lux: Double

        /// How long a hold lasts with the room unchanged.
        static let duration: TimeInterval = 20 * 60
        /// How far the room may move before a hold ends early: double or half
        /// the light it was set in. Opening the blinds is a new situation.
        static let roomChange = 2.0

        var expires: Date { since.addingTimeInterval(Self.duration) }

        func isOver(now: Date, lux current: Double) -> Bool {
            if now >= expires { return true }
            let ratio = (current + 1) / (lux + 1)
            return ratio >= Self.roomChange || ratio <= 1 / Self.roomChange
        }
    }
}
