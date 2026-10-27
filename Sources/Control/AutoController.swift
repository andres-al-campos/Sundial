import Foundation
import AppKit

/// Auto mode: reads the room's light once a second and eases the monitor to
/// your level times the room (brightness), the contrast that goes with it, and
/// the clock's Night Shift. See `RoomLight` for the rules.
///
/// Needs no presets. While the sensor gives no reading (lid closed, no sensor)
/// it keeps the last room it saw, or 100 lux before the first.
@MainActor
final class AutoController {
    private weak var state: AppState?
    private var controller: DDCController?
    private var timer: Timer?
    private var smoother = RoomLight.Smoother()
    private var lastTick: Date?
    private var missedReadings = 0

    /// What the monitor is being eased through, before rounding.
    private var shown: (brightness: Double, contrast: Double, nightShift: Double)?
    /// The last value written for each parameter, so only changes are sent.
    private var written: [String: Int] = [:]
    private var lastLogged = Date.distantPast
    private var lastRawLux: Double?

    /// Per-second limits on how fast the monitor moves: brightness and contrast
    /// cross their full range in 20 seconds, Night Shift in ~1.5 minutes.
    private static let maxStep = (brightness: 5.0, contrast: 5.0, nightShift: 1.0)
    /// Readings missed in a row before Auto says the sensor dropped out.
    private static let missesBeforeDropout = 3

    func start(state: AppState, controller: DDCController) {
        guard timer == nil else { return }
        self.state = state
        self.controller = controller
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state?.applyOnWake == true else { return }
                    self.forceApply()
                }
            }
        }
        tick()
    }

    /// Send every parameter on the next tick, whether or not it changed: after
    /// wake, a preview, or a mode switch the monitor may not show what was last
    /// written.
    func forceApply() {
        written = [:]
        tick()
    }

    /// Re-evaluate now rather than on the next tick.
    func refresh() {
        tick()
    }

    /// Brightness set by hand from Auto's slider: shown at once, and kept as
    /// the level for this room, so other rooms scale from it. Saved and logged
    /// once, when the drag ends (`done`).
    func setBrightness(_ brightness: Int, done: Bool) {
        guard let state else { return }
        let lux = state.roomLux ?? RoomLight.referenceLux
        state.autoLevel = RoomLight.level(forBrightness: Double(brightness), lux: lux)
        let contrast = RoomLight.contrast(brightness: Double(brightness))
        shown = (Double(brightness), contrast, shown?.nightShift ?? Double(state.autoNightShift))
        state.autoBrightness = brightness
        write("hardwareBrightness", brightness)
        write("hardwareContrast", Int(contrast.rounded()))
        if done {
            state.save()
            log(force: true)
        }
    }

    // MARK: - Tick

    private func tick() {
        guard let state, let controller, state.isSetUp else { return }
        controller.cliPath = state.cliPath
        controller.displayName = state.displayName

        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 1
        lastTick = now

        guard state.mode == .auto else {
            shown = nil
            written = [:]
            return
        }

        if let raw = AmbientLightSensor.lux() {
            missedReadings = 0
            lastRawLux = raw
            state.roomLux = smoother.add(lux: raw, dt: dt)
            if !state.sensorReading { state.sensorReading = true }
        } else {
            missedReadings += 1
            lastRawLux = nil
            if missedReadings == Self.missesBeforeDropout {
                print("[Sundial] No room light reading (lid closed, sensor covered, or no sensor). Keeping the last room seen until it's back.")
                state.sensorReading = false
            }
        }

        // A preset preview owns the monitor until it ends.
        guard state.previewingPresetID == nil else { return }

        let lux = state.roomLux ?? RoomLight.referenceLux
        let brightness = RoomLight.brightness(level: state.autoLevel, lux: lux)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let target = (brightness: brightness,
                      contrast: RoomLight.contrast(brightness: brightness),
                      nightShift: RoomLight.nightShift(minuteOfDay: (comps.hour ?? 0) * 60 + (comps.minute ?? 0)))

        var s = shown ?? target
        s.brightness = RoomLight.step(s.brightness, toward: target.brightness, maxStep: Self.maxStep.brightness * dt)
        s.contrast = RoomLight.step(s.contrast, toward: target.contrast, maxStep: Self.maxStep.contrast * dt)
        s.nightShift = RoomLight.step(s.nightShift, toward: target.nightShift, maxStep: Self.maxStep.nightShift * dt)
        shown = s
        send(state)
        log(force: false)
    }

    private func send(_ state: AppState) {
        guard let s = shown else { return }
        let b = Int(s.brightness.rounded()), c = Int(s.contrast.rounded()), n = Int(s.nightShift.rounded())
        if state.autoBrightness != b { state.autoBrightness = b }
        if state.autoNightShift != n { state.autoNightShift = n }
        write("hardwareBrightness", b)
        write("hardwareContrast", c)
        write("nightShift", n)
    }

    private func write(_ param: String, _ value: Int) {
        guard written[param] != value, let controller else { return }
        written[param] = value
        Task { await controller.applySingle(param, value: value) }
    }

    // MARK: - Log

    /// One line a minute, and one whenever you set the brightness, so a few days
    /// of use show what you chose against how bright the room was. Kept next to
    /// config.json as room-log.csv.
    private static let logURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Sundial/room-log.csv")
    }()

    private func log(force: Bool) {
        guard let state, let s = shown else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLogged) >= 60 else { return }
        lastLogged = now
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withInternetDateTime])
        let fields = [
            stamp,
            lastRawLux.map { String(format: "%.1f", $0) } ?? "",
            state.roomLux.map { String(format: "%.1f", $0) } ?? "",
            String(Int(s.brightness.rounded())),
            String(Int(s.contrast.rounded())),
            String(Int(s.nightShift.rounded())),
            force ? String(format: "%.1f", state.autoLevel) : "",
        ]
        let line = fields.joined(separator: ",") + "\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.logURL.path) {
            fm.createFile(atPath: Self.logURL.path, contents: Data("time,lux,lux_avg,brightness,contrast,night_shift,level_set\n".utf8))
        }
        guard let handle = try? FileHandle(forWritingTo: Self.logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
