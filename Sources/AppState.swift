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

    /// Auto follows the room's light between `darkEnd` and `brightEnd`;
    /// Schedule applies the presets by time of day.
    enum Mode: String, Codable { case auto, schedule }
    @Published var mode: Mode = .auto
    @Published var darkEnd = RoomLight.End(brightness: 0, contrast: 7)
    @Published var brightEnd = RoomLight.End(brightness: 42, contrast: 69)

    // Auto's live state, set by AutoController and not saved.

    /// The averaged room light, or nil while there's no reading (no sensor, lid
    /// closed). Nil in Auto means the schedule is driving the monitor.
    @Published var roomLux: Double?
    /// The brightness Auto has the monitor at right now.
    @Published var autoBrightness: Int = 0
    /// A brightness set by hand in Auto, until it lapses.
    @Published var hold: RoomLight.Hold?
    /// The end being previewed on the monitor while its card is edited.
    @Published var previewingEnd: EndKind?
    enum EndKind { case dark, bright }

    /// True when Auto, not the schedule, owns the monitor.
    var autoDrivesMonitor: Bool { mode == .auto && roomLux != nil }

    /// Set by the app at startup: Auto re-evaluates at once instead of on its
    /// next tick (an end edited, the mode switched).
    var onAutoChanged: (() -> Void)?

    /// Set by the app at startup: hold Auto's brightness at a value, or nil to
    /// end the hold and ease back to the room.
    var onHold: ((Int?) -> Void)?

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

    private let configURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Sundial")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    init() {
        load()
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
        var darkEnd: RoomLight.End?
        var brightEnd: RoomLight.End?
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
            darkEnd: darkEnd,
            brightEnd: brightEnd
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
        // A config from before Auto takes its ends from the presets: the dimmest
        // for a dark room, the brightest for a bright one.
        let byBrightness = presets.sorted { $0.hardwareBrightness < $1.hardwareBrightness }
        darkEnd = config.darkEnd ?? byBrightness.first.map { .init(brightness: $0.hardwareBrightness, contrast: $0.hardwareContrast) } ?? darkEnd
        brightEnd = config.brightEnd ?? byBrightness.last.map { .init(brightness: $0.hardwareBrightness, contrast: $0.hardwareContrast) } ?? brightEnd
    }

    func end(_ kind: EndKind) -> RoomLight.End {
        kind == .dark ? darkEnd : brightEnd
    }

    /// `persist: false` while a slider is mid-drag; the release saves.
    func setEnd(_ kind: EndKind, _ end: RoomLight.End, persist: Bool = true) {
        if kind == .dark { darkEnd = end } else { brightEnd = end }
        if persist { save() }
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
