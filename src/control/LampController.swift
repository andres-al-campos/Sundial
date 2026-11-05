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
    private var readingKey = false
    private var returning = false
    /// The last tick sent nothing, so what the bulbs read isn't a fade still landing. Read
    /// sooner, the way back's half second would be replaced by the usual 30.
    private var settled = false
    private var returnStarted = Date.distantPast
    /// While paused a preview returns to what the lamps were, since the day isn't
    /// theirs to follow: Pause is there so the Hue app can use them.
    private var beforePreview: [String: LightDay.State]?
    private var previewed: Set<String> = []
    /// Kept through `refresh`, unlike `sent`: it's how a lamp the day dimmed to off
    /// is told from one someone switched off.
    private var offByDay: Set<String> = []
    /// Switched off by hand when a preview began. The preview lights them, and the tick after it
    /// would read them as on and keep them so: "a lamp switched off by hand stays off".
    private var offByHandBeforePreview: Set<String>?
    // One line per tick, because the status line keeps saying "Paired" through a
    // stall: on 2026-11-01 the lamps sat on Night for at least 50 minutes.
    private static let log = Logger(subsystem: "com.aurende.sundial", category: "lamps")

    static let interval: TimeInterval = 30
    /// A bulb added or renamed in the Hue app is seen within this long.
    static let rereadBulbs: TimeInterval = 600
    static let previewPace: TimeInterval = 0.5
    static let returnFade: TimeInterval = 0.5
    static let previewBulbsPerPace = 2.0

    func start(state: AppState) {
        guard timer == nil else { return }
        self.state = state
        if let host = state.hueHost {
            // Off the main thread: this waits for as long as a Keychain prompt stays
            // up, and on the main thread that held the whole launch, monitor included.
            readingKey = true
            Task {
                let key = await Task.detached { HueBridge.savedKey(host: host) }.value
                bridge = HueBridge(host: host, key: key)
                readingKey = false
                refresh()
            }
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
        let now = Date()
        let warm = SunClock.schedule(on: now, bedtime: state.bedtime), sun = SunClock.sun(on: now)
        let marks = LightDay.Marks(warm: warm, sun: sun)
        if state.lights == nil {
            let scenes = try await bridge.scenes()
            days = LightDay.imported(scenes: Dictionary(scenes.map { ($0.name, $0.lamps) }, uniquingKeysWith: { a, _ in a }),
                                     times: LampBlend.defaultTimes(warm: warm, sun: sun),
                                     marks: marks)
        }
        let old = state.lights ?? []
        let merged = found.map { l -> LightDay.Bulb in
            var b = old.first { $0.id == l.id } ?? LightDay.Bulb(id: l.id, deviceID: l.deviceID, name: l.name, keys: days[l.id] ?? LightDay.defaultKeys(marks: marks))
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
        returning = false
        guard previewTask == nil, let bridge, bridge.isPaired else { return }
        previewTask = Task {
            if state?.lampsFollow == false, beforePreview == nil {
                do { beforePreview = try await bridge.lampStates() }
                catch { state?.lampStatus = error.localizedDescription }
            } else if state?.lampsFollow == true, offByHandBeforePreview == nil {
                let lit = (try? await bridge.lampsOn()) ?? [:]
                offByHandBeforePreview = Set(lit.filter { !$0.value }.keys).subtracting(offByDay)
            }
            while !pendingPreview.isEmpty {
                let batch = pendingPreview
                previewed.formUnion(batch.keys)
                pendingPreview = [:]
                let started = Date()
                do {
                    for (id, s) in batch {
                        // Not someone leaving the room: the way back has to be able to light it again.
                        if !s.on { offByDay.insert(id) }
                        settled = false
                        try await bridge.set(lamp: id, to: s, fade: Self.previewPace)
                    }
                } catch {
                    state?.lampStatus = error.localizedDescription
                }
                // Cut short on letting go: the way back is one call a bulb, nowhere near what
                // slows the bridge, and waiting here is time the bulb sits on the preview.
                let until = started.addingTimeInterval(Self.previewPace * Double(max(batch.count, 1)) / Self.previewBulbsPerPace)
                while previewing, Date() < until { try? await Task.sleep(for: .milliseconds(20)) }
            }
            previewTask = nil
        }
    }

    /// Back to the day quickly, once what a preview already sent has landed: left to
    /// the usual 30-second fade, a preview looks like it stuck.
    func endPreview() {
        pendingPreview = [:]
        previewing = false
        returning = true
        returnStarted = Date()
        // Only these moved. Resending the rest made the one you were watching wait its turn.
        for id in previewed { sent[id] = nil }
        Task {
            await previewTask?.value
            while busy { try? await Task.sleep(for: .milliseconds(50)) }
            guard !previewing else { return }
            if let before = beforePreview {
                await restore(before)
            } else {
                await switchBackOff()
                await tick()
            }
        }
    }

    /// A hold made since is the user asking for the bulb now, so that one stays on.
    private func switchBackOff() async {
        guard let ids = offByHandBeforePreview else { return }
        offByHandBeforePreview = nil
        guard let bridge else { return }
        let holds = state?.holds ?? [:], bulbs = state?.lights ?? []
        let off = LightDay.State(on: false, brightness: 0, xy: .init(x: 0, y: 0))
        for id in ids.intersection(previewed) where LightDay.holdOwner(of: id, in: bulbs, holds: holds) == nil {
            offByDay.remove(id)
            sent[id] = nil
            do { try await bridge.set(lamp: id, to: off, fade: Self.returnFade) }
            catch { state?.lampStatus = error.localizedDescription }
        }
    }

    private func restore(_ before: [String: LightDay.State]) async {
        beforePreview = nil
        returning = false
        guard let bridge else { return }
        let holds = state?.holds ?? [:], bulbs = state?.lights ?? []
        let ids = previewed.union(holds.keys)
        previewed = []
        do {
            for id in ids {
                let held = LightDay.holdOwner(of: id, in: bulbs, holds: holds).flatMap { holds[$0]?.look }
                if let s = held ?? before[id] { try await bridge.set(lamp: id, to: s, fade: Self.returnFade) }
            }
        } catch {
            state?.lampStatus = error.localizedDescription
        }
    }

    /// What the lamps are doing, for the card that changes a bulb right now.
    func lampsNow() async throws -> [String: LightDay.State] {
        guard let bridge, bridge.isPaired else {
            throw HueError("Sundial isn't paired with the bridge. Open Settings → Lamps and pair it.")
        }
        return try await bridge.lampStates()
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
        // Letting go of a slider saves, which asks for a tick before the preview has handed back, and its last
        // send can still be on its way. Landing after this tick's it would stay: `sent` says the
        // bulb is on target, and under a hold the target never moves to correct it.
        if !previewing { await previewTask?.value }
        guard let state, !busy else {
            Self.log.notice("tick skipped: the last one hasn't finished")
            return
        }
        guard !readingKey else {
            state.lampStatus = "Waiting for the Keychain. Choose Always Allow in its prompt."
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
            let ended = state.holds.filter { $0.value.until <= Date() }.keys
            for id in ended { state.holds[id] = nil }
            // Above the pause, since paused is when the Hue app may have them doing anything.
            state.lampsRead = try await bridge.lampStates()
            guard state.lampsFollow else {
                state.lampStatus = "Paired · paused"
                return
            }
            guard !previewing, !state.movingKeyframe else { return }
            let moved = previewed
            previewed = []
            let now = Date()
            let marks = LightDay.Marks(warm: SunClock.schedule(on: now, bedtime: state.bedtime), sun: SunClock.sun(on: now))
            let comps = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
            let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            let bulbs = state.lights ?? []
            let lit = try await bridge.lampsOn()
            let backFirst = bulbs.filter { moved.contains($0.id) } + bulbs.filter { !moved.contains($0.id) }
            var sends = 0, leftOff = 0, putBack = 0
            for bulb in backFirst {
                let hold = LightDay.holdOwner(of: bulb.id, in: bulbs, holds: state.holds).flatMap { state.holds[$0]?.look }
                guard let target = hold ?? LightDay.state(LightDay.keys(of: bulb, in: bulbs), at: Double(minute), marks: marks),
                      let isOn = lit[bulb.id] else { continue }
                if isOn { offByDay.remove(bulb.id) }
                // Off on the card isn't someone leaving the room: Return to schedule has
                // to be able to light it again.
                if hold?.on == false { offByDay.insert(bulb.id) }
                let send = LightDay.send(targetOn: target.on, lampIsOn: isOn, dayTurnedItOff: offByDay.contains(bulb.id))
                if send == .leave {
                    // Forgotten, so the tick after it's switched back on catches it up.
                    sent[bulb.id] = nil
                    leftOff += 1
                    continue
                }
                // Something else on the bridge can move a bulb, such as a routine from the Hue app.
                // A moving day sets it back anyway, but a hold's target stands still, as does a flat
                // stretch's, and with nothing to send the routine would have the bulb to itself.
                let drifted = settled && state.lampsRead[bulb.id].map { LightDay.drifted($0, from: target) } == true
                if drifted { putBack += 1 }
                guard sent[bulb.id] != target || drifted else { continue }
                try await bridge.set(lamp: bulb.id, to: target, fade: returning ? Self.returnFade : Self.interval, power: send == .power)
                sent[bulb.id] = target
                sends += 1
                if send == .power {
                    if target.on { offByDay.remove(bulb.id) } else { offByDay.insert(bulb.id) }
                }
            }
            if returning {
                let seconds = Date().timeIntervalSince(returnStarted)
                Self.log.notice("back to the day: sent \(sends) within \(seconds, format: .fixed(precision: 2))s of letting go")
            }
            returning = false
            settled = sends == 0
            state.lampStatus = "Paired · following the day"
            Self.log.notice("tick at minute \(minute): sent \(sends), put back \(putBack), left \(leftOff) off, \(state.lampStatus, privacy: .public)")
        } catch {
            state.lampStatus = error.localizedDescription
            Self.log.error("tick failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
