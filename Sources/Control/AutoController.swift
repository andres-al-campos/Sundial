import Foundation
import AppKit

/// Auto mode: reads the room's light once a second and eases the monitor's
/// brightness and contrast to the point between the two ends that the room
/// picks. Night Shift still follows the schedule's presets, since warmth is
/// about the hour, not the light.
///
/// While there's no reading (no sensor, lid closed) Auto stands aside and the
/// Scheduler drives the monitor as in Schedule mode.
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

    /// Per-second limits on how fast the monitor moves. Brightness and contrast
    /// take ~3 minutes across their full range, Night Shift ~1.5.
    private static let maxStep = (brightness: 0.5, contrast: 0.5, nightShift: 1.0)
    /// Readings missed in a row before Auto hands the monitor to the schedule.
    private static let missesBeforeHandoff = 3

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

    /// Brightness set by hand from Auto's slider. It moves the monitor at once
    /// and holds until it lapses (see `RoomLight.Hold`).
    func setHeld(brightness: Int) {
        guard let state, let lux = state.roomLux else { return }
        state.hold = RoomLight.Hold(brightness: brightness, since: Date(), lux: lux)
        shown?.brightness = Double(brightness)
        state.autoBrightness = brightness
        write("hardwareBrightness", brightness)
        log(force: true)
    }

    func endHold() {
        state?.hold = nil
        log(force: true)
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
            standAside(state)
            return
        }

        guard let raw = AmbientLightSensor.lux() else {
            missedReadings += 1
            // Said once per dropout, including one that starts at launch.
            if missedReadings == Self.missesBeforeHandoff {
                print("[Sundial] No room light reading (lid closed, sensor covered, or no sensor). Following the schedule until it's back.")
                if state.roomLux != nil {
                    standAside(state)
                    state.onScheduleChanged?()
                }
            }
            return
        }
        missedReadings = 0
        lastRawLux = raw
        let lux = smoother.add(lux: raw, dt: dt)
        let takingOver = state.roomLux == nil
        state.roomLux = lux

        // A preset preview owns the monitor until it ends.
        guard state.previewingPresetID == nil else { return }

        let nightShift = Double(scheduledNightShift(state))

        // Taking over from the schedule: start from what it last applied, so
        // the hand-over eases instead of jumping.
        if takingOver || shown == nil {
            if let preset = scheduledPreset(state) {
                shown = (Double(preset.hardwareBrightness), Double(preset.hardwareContrast), Double(preset.nightShift))
            }
        }

        // An end being edited is shown as is, so you see what you're setting.
        if let kind = state.previewingEnd {
            let end = state.end(kind)
            shown = (Double(end.brightness), Double(end.contrast), nightShift)
            send(state)
            return
        }

        if let hold = state.hold, hold.isOver(now: now, lux: lux) {
            state.hold = nil
            log(force: true)
        }

        let t = RoomLight.position(lux: lux)
        let auto = RoomLight.target(position: t, dark: state.darkEnd, bright: state.brightEnd)
        let target = (brightness: state.hold.map { Double($0.brightness) } ?? auto.brightness,
                      contrast: auto.contrast,
                      nightShift: nightShift)

        var s = shown ?? target
        s.brightness = RoomLight.step(s.brightness, toward: target.brightness, maxStep: Self.maxStep.brightness * dt)
        s.contrast = RoomLight.step(s.contrast, toward: target.contrast, maxStep: Self.maxStep.contrast * dt)
        s.nightShift = RoomLight.step(s.nightShift, toward: target.nightShift, maxStep: Self.maxStep.nightShift * dt)
        shown = s
        send(state)
        log(force: false)
    }

    private func standAside(_ state: AppState) {
        if state.roomLux != nil { state.roomLux = nil }
        if state.hold != nil { state.hold = nil }
        shown = nil
        written = [:]
        smoother = RoomLight.Smoother()
    }

    private func send(_ state: AppState) {
        guard let s = shown else { return }
        let b = Int(s.brightness.rounded()), c = Int(s.contrast.rounded()), n = Int(s.nightShift.rounded())
        if state.autoBrightness != b { state.autoBrightness = b }
        write("hardwareBrightness", b)
        write("hardwareContrast", c)
        write("nightShift", n)
    }

    private func write(_ param: String, _ value: Int) {
        guard written[param] != value, let controller else { return }
        written[param] = value
        Task { await controller.applySingle(param, value: value) }
    }

    // MARK: - Schedule

    private func scheduledPreset(_ state: AppState) -> Preset? {
        Scheduler.activeEntry(in: state.schedule, presets: state.presets, at: Date())
            .flatMap { state.preset(for: $0.presetID) }
    }

    private func scheduledNightShift(_ state: AppState) -> Int {
        scheduledPreset(state)?.nightShift ?? 0
    }

    // MARK: - Log

    /// One line a minute, and one whenever a hold starts or ends, so a few days
    /// of use show what you set against how bright the room was. Kept next to
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
            lastRawLux.map { String(format: "%.0f", $0) } ?? "",
            state.roomLux.map { String(format: "%.0f", $0) } ?? "",
            String(Int(s.brightness.rounded())),
            String(Int(s.contrast.rounded())),
            String(Int(s.nightShift.rounded())),
            state.hold.map { String($0.brightness) } ?? "",
        ]
        let line = fields.joined(separator: ",") + "\n"
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.logURL.path) {
            fm.createFile(atPath: Self.logURL.path, contents: Data("time,lux,lux_avg,brightness,contrast,night_shift,held\n".utf8))
        }
        guard let handle = try? FileHandle(forWritingTo: Self.logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
