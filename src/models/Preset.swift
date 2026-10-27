import Foundation

struct Preset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String

    /// Brightness (0–100). Controls the monitor's actual backlight via DDC.
    /// Driven via BetterDisplay CLI (`-hardwareBrightness`).
    var hardwareBrightness: Int

    /// Hardware contrast (0–100). Controls monitor contrast via DDC (free feature).
    /// Driven via BetterDisplay CLI (`-hardwareContrast`).
    var hardwareContrast: Int

    /// Night Shift strength (0–100). 0 = off, 100 = maximum warmth.
    /// Driven via macOS's built-in Night Shift (CoreBrightness private framework).
    var nightShift: Int

    /// When false, the scheduler skips any schedule entry pointing at this preset.
    /// Temporary disable without deleting. Defaults true (back-compat with older configs).
    var enabled: Bool = true

    static let defaults: [Preset] = [
        Preset(name: "Morning", hardwareBrightness: 70, hardwareContrast: 75, nightShift: 30),
        Preset(name: "Day",     hardwareBrightness: 100, hardwareContrast: 75, nightShift: 0),
        Preset(name: "Evening", hardwareBrightness: 60, hardwareContrast: 70, nightShift: 50),
        Preset(name: "Night",   hardwareBrightness: 30, hardwareContrast: 60, nightShift: 90),
    ]

    /// Linear interpolation toward another preset (used for smooth transitions)
    func lerp(to other: Preset, t: Double) -> Preset {
        func lerpInt(_ a: Int, _ b: Int) -> Int { Int(Double(a) + (Double(b) - Double(a)) * t) }
        return Preset(
            id: id,
            name: name,
            hardwareBrightness: lerpInt(hardwareBrightness, other.hardwareBrightness),
            hardwareContrast:   lerpInt(hardwareContrast, other.hardwareContrast),
            nightShift:         lerpInt(nightShift, other.nightShift),
            enabled:            enabled
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, hardwareBrightness, hardwareContrast, nightShift, enabled
    }

    init(id: UUID = UUID(), name: String, hardwareBrightness: Int, hardwareContrast: Int, nightShift: Int, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.hardwareBrightness = hardwareBrightness
        self.hardwareContrast = hardwareContrast
        self.nightShift = nightShift
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.hardwareBrightness = (try? c.decode(Int.self, forKey: .hardwareBrightness)) ?? 70
        self.hardwareContrast   = (try? c.decode(Int.self, forKey: .hardwareContrast)) ?? 75
        self.nightShift = try c.decode(Int.self, forKey: .nightShift)
        self.enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    }
}
