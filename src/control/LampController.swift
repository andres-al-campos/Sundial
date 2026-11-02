import Foundation
import AppKit
import OSLog

/// The Hue lamps follow the day: Sundial reads the scenes on the bridge, places
/// them on the day (`LampBlend.defaultTimes`), and every 30 seconds fades each
/// lamp to the blend for now. Each fade lasts until the next, so the lamps move
/// continuously instead of in steps. It runs in Auto and Schedule alike: the
/// lamps follow the clock, not the monitor's mode.
@MainActor
final class LampController {
    private weak var state: AppState?
    private var bridge: HueBridge?
    private var timer: Timer?
    private var scenes: [HueBridge.Scene] = []
    private var scenesRead = Date.distantPast
    private var sent: [String: LampBlend.LampState] = [:]
    private var busy = false
    // One line per tick, because the status line keeps saying "Paired" through a
    // stall: on 2026-11-01 the lamps sat on Night for at least 50 minutes.
    private static let log = Logger(subsystem: "com.aurende.sundial", category: "lamps")

    static let interval: TimeInterval = 30
    /// Scenes edited in the Hue app are seen within this long.
    static let rereadScenes: TimeInterval = 600

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
                scenesRead = .distantPast
                refresh()
            } catch {
                state.lampStatus = error.localizedDescription
            }
        }
    }

    /// "Between MidNight and DuskLight", or the scene itself while one holds.
    private static func `where`(_ frames: [LampBlend.Keyframe], _ minute: Int) -> String {
        let sorted = frames.sorted { $0.minute < $1.minute }
        guard let i = sorted.lastIndex(where: { $0.minute <= minute }) ?? sorted.indices.last else { return "" }
        let a = sorted[i], b = sorted[(i + 1) % sorted.count]
        let gap = (b.minute - a.minute + 24 * 60) % (24 * 60)
        let since = (minute - a.minute + 24 * 60) % (24 * 60)
        if sorted.count == 1 || (a.holds && since < gap - LampBlend.settle) { return "lamps at \(a.name)" }
        return "lamps between \(a.name) and \(b.name)"
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
        guard state.lampsFollow else {
            state.lampStatus = "Paired · not following"
            return
        }
        busy = true
        defer { busy = false }
        do {
            if Date().timeIntervalSince(scenesRead) > Self.rereadScenes {
                scenes = try await bridge.scenes()
                scenesRead = Date()
            }
            let now = Date()
            let frames = LampBlend.defaultTimes(warm: SunClock.schedule(on: now, bedtime: state.bedtime), sun: SunClock.sun(on: now))
                .compactMap { t in
                    scenes.first { $0.name == t.name }.map {
                        LampBlend.Keyframe(minute: t.minute, name: t.name, lamps: $0.lamps, holds: t.holds)
                    }
                }
            guard !frames.isEmpty else {
                state.lampStatus = "None of the scenes Sundial uses (Morning, Noon, Twilight, Evening, Night, MidNight, DuskLight) are on the bridge. Make them in the Hue app."
                return
            }
            let comps = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
            let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            var sends = 0
            for (id, target) in LampBlend.blend(frames, at: minute) where sent[id] != target {
                try await bridge.set(lamp: id, to: target, fade: Self.interval)
                sent[id] = target
                sends += 1
            }
            state.lampStatus = "Paired · " + Self.where(frames, minute)
            Self.log.notice("tick at minute \(minute): sent \(sends), \(state.lampStatus, privacy: .public)")
        } catch {
            state.lampStatus = error.localizedDescription
            Self.log.error("tick failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
