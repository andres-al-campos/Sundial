import Foundation
import AppKit
import OSLog

/// The Hue lamps follow the day: every 30 seconds each bulb fades to where its
/// keyframes put it now (`LightDay`). Each fade lasts until the next, so the lamps
/// move continuously instead of in steps. It runs in Auto and Schedule alike: the
/// lamps follow the clock, not the monitor's mode.
@MainActor
final class LampController {
    private weak var state: AppState?
    private var bridge: HueBridge?
    private var timer: Timer?
    private var bulbsRead = Date.distantPast
    private var sent: [String: LightDay.State] = [:]
    private var previewing = false
    private var pendingPreview: [String: LightDay.State] = [:]
    private var previewTask: Task<Void, Never>?
    private var busy = false
    // One line per tick, because the status line keeps saying "Paired" through a
    // stall: on 2026-11-01 the lamps sat on Night for at least 50 minutes.
    private static let log = Logger(subsystem: "com.aurende.sundial", category: "lamps")

    static let interval: TimeInterval = 30
    /// A bulb added or renamed in the Hue app is seen within this long.
    static let rereadBulbs: TimeInterval = 600
    static let previewPace: TimeInterval = 0.5
    static let previewBulbsPerPace = 2.0

    func start(state: AppState) {
        guard timer == nil else { return }
        self.state = state
        if let host = state.hueHost {
            bridge = HueBridge(host: host, key: HueBridge.savedKey(host: host))
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Set the lamps for now, sending every lamp whether or not it changed.
    func refresh() {
        sent = [:]
        Task { await tick() }
    }

    func pair() {
        guard let state else { return }
        Task {
            state.lampStatus = "Looking for the bridge…"
            guard let host = await HueBridge.discover() else {
                state.lampStatus = "No bridge found. Check it's on and on this network, then pair again."
                return
            }
            let b = HueBridge(host: host, key: nil)
            state.lampStatus = "Press the button on top of the bridge"
            do {
                try await b.pair()
                bridge = b
                state.hueHost = host
                state.lampsFollow = true
                state.save()
                bulbsRead = .distantPast
                refresh()
            } catch {
                state.lampStatus = error.localizedDescription
            }
        }
    }

    /// The bulbs on the bridge into the Lights window's rows, importing the
    /// scenes the first time. After that Sundial holds the settings, and scenes
    /// edited in the Hue app are no longer read.
    private func syncBulbs(_ bridge: HueBridge, _ state: AppState) async throws {
        guard Date().timeIntervalSince(bulbsRead) > Self.rereadBulbs else { return }
        let found = try await bridge.lights().sorted { $0.name < $1.name }
        bulbsRead = Date()
        var days: [String: [LightDay.Key]] = [:]
        if state.lights == nil {
            let now = Date()
            let warm = SunClock.schedule(on: now, bedtime: state.bedtime), sun = SunClock.sun(on: now)
            let scenes = try await bridge.scenes()
            days = LightDay.imported(scenes: Dictionary(scenes.map { ($0.name, $0.lamps) }, uniquingKeysWith: { a, _ in a }),
                                     times: LampBlend.defaultTimes(warm: warm, sun: sun),
                                     marks: LightDay.Marks(warm: warm, sun: sun))
        }
        let old = state.lights ?? []
        let merged = found.map { l -> LightDay.Bulb in
            var b = old.first { $0.id == l.id } ?? LightDay.Bulb(id: l.id, deviceID: l.deviceID, name: l.name, keys: days[l.id] ?? [])
            b.name = l.name
            b.deviceID = l.deviceID
            return b
        }
        // A parent that left the bridge leaves its followers with their own day.
        let lights = merged.map { b -> LightDay.Bulb in
            var b = b
            if let p = b.parent, !merged.contains(where: { $0.id == p }) {
                b.keys = old.first { $0.id == p }?.keys ?? b.keys
                b.parent = nil
            }
            return b
        }
        if lights != state.lights {
            state.lights = lights
            state.save()
        }
    }

    /// Show these on the bulbs now, from the Lights window. Stands in for the
    /// schedule until `endPreview`. Only the newest state is sent, at the rate
    /// the bridge kept up with on 2026-11-01: above 5 calls a second its
    /// answers started taking seconds.
    func preview(_ states: [String: LightDay.State]) {
        pendingPreview.merge(states) { _, new in new }
        previewing = true
        guard previewTask == nil, let bridge, bridge.isPaired else { return }
        previewTask = Task {
            while !pendingPreview.isEmpty {
                let batch = pendingPreview
                pendingPreview = [:]
                let started = Date()
                do {
                    for (id, s) in batch { try await bridge.set(lamp: id, to: s, fade: Self.previewPace) }
                } catch {
                    state?.lampStatus = error.localizedDescription
                }
                let spare = Self.previewPace * Double(max(batch.count, 1)) / Self.previewBulbsPerPace - Date().timeIntervalSince(started)
                if spare > 0 { try? await Task.sleep(for: .seconds(spare)) }
            }
            previewTask = nil
        }
    }

    func endPreview() {
        pendingPreview = [:]
        previewing = false
        refresh()
    }

    func scenesAsStored() async throws -> Data {
        guard let bridge, bridge.isPaired else {
            throw HueError("Sundial isn't paired with the bridge. Open Settings → Lamps and pair it.")
        }
        return try await bridge.scenesAsStored()
    }

    func rename(device id: String, to name: String) {
        guard let bridge else { return }
        Task {
            do { try await bridge.rename(device: id, to: name) }
            catch { state?.lampStatus = error.localizedDescription }
        }
    }

    private func tick() async {
        guard let state, !busy else {
            Self.log.notice("tick skipped: the last one hasn't finished")
            return
        }
        guard let bridge, bridge.isPaired else {
            state.lampStatus = "Not paired"
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await syncBulbs(bridge, state)
            guard state.lampsFollow else {
                state.lampStatus = "Paired · paused"
                return
            }
            guard !previewing else { return }
            let now = Date()
            let marks = LightDay.Marks(warm: SunClock.schedule(on: now, bedtime: state.bedtime), sun: SunClock.sun(on: now))
            let comps = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
            let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let bulbs = state.lights ?? []
            var sends = 0
            for bulb in bulbs {
                guard let target = LightDay.state(LightDay.keys(of: bulb, in: bulbs), at: Double(minute), marks: marks),
                      sent[bulb.id] != target else { continue }
                try await bridge.set(lamp: bulb.id, to: target, fade: Self.interval)
                sent[bulb.id] = target
                sends += 1
            }
            state.lampStatus = "Paired · following the day"
            Self.log.notice("tick at minute \(minute): sent \(sends), \(state.lampStatus, privacy: .public)")
        } catch {
            state.lampStatus = error.localizedDescription
            Self.log.error("tick failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
