import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var schedule: [ScheduleEntry] = []
    @Published var activePresetID: UUID?
    @Published var displayName: String = ""
    @Published var cliPath: String = "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
    @Published var applyOnWake: Bool = true
    @Published var launchAtLogin: Bool = false

    /// Auto sets the monitor from the room's light and the clock; Schedule
    /// applies the presets by time of day.
    enum Mode: String, Codable { case auto, schedule }
    @Published var mode: Mode = .auto
    /// How bright you like the screen, as the brightness at 100 lux. The room's
    /// light multiplies it (see `RoomLight`). Set by dragging Auto's slider.
    @Published var dayLevel: Double = RoomLight.defaultLevel
    /// Contrast per point of brightness. Set by dragging Auto's Contrast slider.
    @Published var autoContrastScale: Double = RoomLight.defaultContrastScale
    /// The brightness the evening reaches by bedtime. Set by dragging
    /// Brightness after bedtime.
    @Published var autoNightMinimum: Double = RoomLight.defaultNightMinimum
    /// The contrast with it. Set by dragging Contrast after bedtime.
    @Published var autoNightContrast: Double = RoomLight.defaultNightContrast
    /// When Night Shift is full and the lamps reach their dimmest scene, in
    /// minutes after midnight. Set in Auto.
    @Published var bedtime: Int = 24 * 60
    /// Where the sun is worked out for, when picked on Settings' map.
    @Published var place: RoomLight.Place? { didSet { SunClock.picked = place } }
    /// The Hue lamps follow their days. False while paused from the Lights window.
    @Published var lampsFollow: Bool = false
    /// Bulbs set by hand until sunrise. A relaunch keeps them: a hold that vanished with an install
    /// would put the room back on the day while it was still wanted.
    @Published var holds: [String: LightDay.Hold] = [:] { didSet { saveHolds() } }
    /// What the bulbs were doing at the last tick, for the room log. Not published: nothing on
    /// screen shows it, and it would redraw every window twice a minute.
    var lampsRead: [String: LightDay.State] = [:]
    /// A keyframe is in the user's hand, so the day is half-edited and the lamps wait for the drop.
    var movingKeyframe = false
    /// Each bulb's day. Nil until the scenes on the bridge have been imported.
    @Published var lights: [LightDay.Bulb]?
    /// Paused from the Lights window, as opposed to never paired or the bridge unreachable.
    var lampsPaused: Bool { !lampsFollow && hueHost != nil && lampStatus.hasPrefix("Paired") }
    /// The lamps aren't on the day: a bulb is held, or they're paused.
    var lampsOffTheDay: Bool { !holds.isEmpty || lampsPaused }
    /// The paired Hue Bridge's host name; its key is in the Keychain.
    @Published var hueHost: String?
    /// What the lamps are doing, or why they aren't, for Settings.
    @Published var lampStatus: String = "Not paired"

    // Auto's live state, set by AutoController and not saved.

    /// The averaged room light. Holds its last value while the sensor gives no
    /// reading; nil only before the first.
    @Published var roomLux: Double?
    /// False while the sensor gives no reading (lid closed, no sensor).
    @Published var sensorReading = false
    /// The brightness Auto has the monitor at right now.
    @Published var autoBrightness: Int = 0
    /// The contrast Auto has the monitor at right now.
    @Published var autoContrast: Int = 0
    /// The Night Shift Auto has set right now.
    @Published var autoNightShift: Int = 0

    /// True when Auto, not the schedule, owns the monitor.
    var autoDrivesMonitor: Bool { mode == .auto }

    /// Set by the app at startup: Auto re-evaluates at once instead of on its
    /// next tick (the mode switched).
    var onAutoChanged: (() -> Void)?

    /// Set by the app at startup: show this brightness now, and keep it as the
    /// level for this room. The flag is true when the drag ends.
    var onSetBrightness: ((Int, Bool) -> Void)?
    /// Set by the app at startup: show this contrast now, and keep it as the
    /// contrast for this brightness. The flag is true when the drag ends.
    var onSetContrast: ((Int, Bool) -> Void)?
    /// Set by the app at startup: find the bridge and pair with it.
    var onPairLamps: (() -> Void)?
    /// Set by the app at startup: set the lamps for now, not on the next tick.
    var onLampsChanged: (() -> Void)?
    /// Set by the app at startup: show these states on the bulbs now.
    var onPreviewLamps: (([String: LightDay.State]) -> Void)?
    /// Set by the app at startup: hand the bulbs back to their days.
    var onEndLampPreview: (() -> Void)?
    /// Set by the app at startup: rename a bulb on the bridge.
    var onRenameBulb: ((_ deviceID: String, _ name: String) -> Void)?
    /// Set by the app at startup: the bridge's scenes, as it holds them.
    var onReadHue: (() async throws -> Data)?
    var onReadLamps: (() async throws -> [String: LightDay.State])?
    /// Set by the app at startup: open the desktop window.
    var onOpenWindow: (() -> Void)?

    /// True once the BetterDisplay path + display name have been verified against
    /// real hardware (a DDC read succeeded). Until then, the menu bar shows the
    /// setup screen instead of presets — Sundial can't control a monitor it can't
    /// reach, and silently-failing sliders are a worse first-run than an honest gate.
    /// Persisted so a returning user with a known-good setup skips onboarding.
    @Published var isSetUp: Bool = false

    /// ID of the preset currently being live-previewed, if any.
    /// While non-nil, the Scheduler suppresses its own apply calls —
    /// the preview owns the monitor until the user ends it.
    @Published var previewingPresetID: UUID?

    /// Set by the app at startup — lets views ask the scheduler to snap back
    /// to the current-time preset when a preview ends.
    var onPreviewEnded: (() -> Void)?

    /// Set by the app at startup — lets views ask the scheduler to re-evaluate
    /// which preset should be active right now (e.g. after toggling Enabled).
    var onScheduleChanged: (() -> Void)?

    /// The section the desktop window shows, and shows again next time it opens.
    @Published var windowSection = UserDefaults.standard.string(forKey: "windowSection").flatMap(WindowSection.init) ?? .presets {
        didSet { UserDefaults.standard.set(windowSection.rawValue, forKey: "windowSection") }
    }

    nonisolated static let supportDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Sundial")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let configURL = AppState.supportDirectory.appendingPathComponent("config.json")
    /// Apart from config.json: a hold is rewritten on every tick of a slider's drag, and a write
    /// that small shouldn't rewrite everything else too.
    private let holdsURL = AppState.supportDirectory.appendingPathComponent("holds.json")

    init() {
        load()
        if let data = try? Data(contentsOf: holdsURL),
           let saved = try? JSONDecoder().decode([String: LightDay.Hold].self, from: data) {
            holds = saved.filter { $0.value.until > Date() }
        }
    }

    private func saveHolds() {
        do {
            try JSONEncoder().encode(holds).write(to: holdsURL, options: .atomic)
        } catch {
            print("[Sundial] Saving the held bulbs failed: \(error). They go back to the day at the next launch.")
        }
    }

    // MARK: - Persistence

    private struct Config: Codable {
        var presets: [Preset]
        var schedule: [ScheduleEntry]
        var displayName: String
        var cliPath: String
        var applyOnWake: Bool
        var launchAtLogin: Bool
        var isSetUp: Bool?
        var mode: Mode?
        // Not `autoLevel`: that one meant a level on the fourth-root curve, and
        // carried over it would land at about half the fitted brightness by day.
        var dayLevel: Double?
        var autoContrastScale: Double?
        var lampsFollow: Bool?
        var bedtime: Int?
        var place: RoomLight.Place?
        var autoNightMinimum: Double?
        var autoNightContrast: Double?
        var hueHost: String?
        var lights: [LightDay.Bulb]?
    }

    func save() {
        let config = Config(
            presets: presets,
            schedule: schedule,
            displayName: displayName,
            cliPath: cliPath,
            applyOnWake: applyOnWake,
            launchAtLogin: launchAtLogin,
            isSetUp: isSetUp,
            mode: mode,
            dayLevel: dayLevel,
            autoContrastScale: autoContrastScale,
            lampsFollow: lampsFollow,
            bedtime: bedtime,
            place: place,
            autoNightMinimum: autoNightMinimum,
            autoNightContrast: autoNightContrast,
            hueHost: hueHost,
            lights: lights
        )
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[Sundial] Save failed: \(error)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            seedDefaults()
            return
        }
        presets = config.presets
        schedule = config.schedule.sorted { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        displayName = config.displayName
        cliPath = config.cliPath
        applyOnWake = config.applyOnWake
        launchAtLogin = config.launchAtLogin
        isSetUp = config.isSetUp ?? false
        mode = config.mode ?? .auto
        dayLevel = config.dayLevel ?? RoomLight.defaultLevel
        autoContrastScale = config.autoContrastScale ?? RoomLight.defaultContrastScale
        lampsFollow = config.lampsFollow ?? false
        bedtime = config.bedtime ?? 24 * 60
        place = config.place
        autoNightMinimum = config.autoNightMinimum ?? RoomLight.defaultNightMinimum
        autoNightContrast = config.autoNightContrast ?? RoomLight.defaultNightContrast
        hueHost = config.hueHost
        lights = config.lights
    }

    // MARK: - Setup validation

    /// Verify the current BetterDisplay path + display name actually reach a
    /// monitor by attempting a DDC brightness read. On success, flips `isSetUp`
    /// to true (unlocking presets) and persists. Returns nil on success, or a
    /// user-facing failure reason on error.
    func validateSetup() async -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Enter your monitor's display name (a partial match of the name shown in BetterDisplay)."
        }
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            return "No BetterDisplay program found at that path. Make sure BetterDisplay is installed, then point this at the BetterDisplay binary inside it (the default path is usually correct)."
        }
        let controller = DDCController(cliPath: cliPath, displayName: trimmedName)
        let reachable = await controller.probe()
        guard reachable else {
            return "Couldn't read brightness from \"\(trimmedName)\". Make sure the name matches the one in BetterDisplay and that the monitor has DDC/CI enabled in its on-screen menu."
        }
        isSetUp = true
        save()
        return nil
    }

    private func seedDefaults() {
        presets = Preset.defaults
        schedule = [
            ScheduleEntry(presetID: presets[0].id, hour: 6,  minute: 30),
            ScheduleEntry(presetID: presets[1].id, hour: 10, minute: 0),
            ScheduleEntry(presetID: presets[2].id, hour: 18, minute: 30),
            ScheduleEntry(presetID: presets[3].id, hour: 22, minute: 0),
        ]
        save()
    }

    // MARK: - Mutations

    /// Whichever mode is now on takes the monitor at once, in full.
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        previewingPresetID = nil
        mode = newMode
        save()
        if newMode == .auto { onPreviewEnded?() } else { onScheduleChanged?() }
    }

    func addPreset(_ preset: Preset) {
        presets.append(preset)
        save()
    }

    func updatePreset(_ preset: Preset) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[i] = preset
        save()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        schedule.removeAll { $0.presetID == id }
        save()
    }

    func addScheduleEntry(_ entry: ScheduleEntry) {
        schedule.append(entry)
        schedule.sort { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        save()
    }

    func updateScheduleEntry(_ entry: ScheduleEntry) {
        guard let i = schedule.firstIndex(where: { $0.id == entry.id }) else { return }
        schedule[i] = entry
        schedule.sort { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        save()
    }

    func deleteScheduleEntry(id: UUID) {
        schedule.removeAll { $0.id == id }
        save()
    }

    func preset(for id: UUID?) -> Preset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }
}
