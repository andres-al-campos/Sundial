import Foundation
import AppKit

@MainActor
class Scheduler {
    private var timer: Timer?
    private var transitionTask: Task<Void, Never>?
    private var lastAppliedEntryID: UUID?
    private var lastAppliedPreset: Preset?
    private var isStarted = false

    private weak var state: AppState?
    private var controller: DDCController?

    func start(state: AppState, controller: DDCController) {
        guard !isStarted else { return }
        isStarted = true

        self.state = state
        self.controller = controller

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick(state: state, controller: controller)
            }
        }
        // Fire immediately
        tick(state: state, controller: controller)

        // On wake, force a full re-apply of the active preset, then kick off rapid
        // ticks so the display keeps correcting as the panel settles.
        //
        // The first apply is unconditional (not gated on `matches()`) on purpose:
        // `matches()` only reads back brightness/contrast over DDC and has no
        // visibility into Night Shift, so a tick-only wake path would never correct
        // Night Shift when brightness/contrast already happen to match. A full
        // `apply()` is idempotent and cheap, so applying it every wake is safe.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.forceApplyActive(state: state, controller: controller)
                    // Rapid ticks at 1s, 2s, 3s, 4s, 5s after wake catch any
                    // brightness/contrast drift as the panel finishes waking.
                    for _ in 0..<5 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        self.tick(state: state, controller: controller)
                    }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        transitionTask?.cancel()
        transitionTask = nil
    }

    /// Called when a preview ends — snap monitor back to whatever the schedule says
    /// *right now* (not whatever we were about to apply). Bypasses the "already applied"
    /// dedupe so the re-apply always happens.
    func reapplyForCurrentTime() {
        guard let state, let controller else { return }
        guard state.isSetUp else { return }
        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        lastAppliedEntryID = entry.id
        lastAppliedPreset = preset
        state.activePresetID = preset.id

        transitionTask?.cancel()
        transitionTask = Task {
            await controller.apply(preset)
        }
    }

    /// Re-evaluate "which preset should be active right now" and apply if it changed.
    /// Call after any edit that can change the answer: enabling/disabling a preset,
    /// toggling a schedule entry, editing a time. Respects ongoing previews.
    func recompute() {
        guard let state, let controller else { return }
        guard state.isSetUp else { return }
        guard state.previewingPresetID == nil else { return }
        lastAppliedEntryID = nil

        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        lastAppliedEntryID = entry.id
        lastAppliedPreset = preset
        state.activePresetID = preset.id

        transitionTask?.cancel()
        transitionTask = Task {
            await controller.apply(preset)
        }
    }

    // MARK: - Wake

    /// Force a full apply of the active preset, bypassing the `matches()` dedupe.
    /// Used on wake so Night Shift (which `matches()` can't read back) is corrected
    /// even when brightness/contrast already match. Respects the user's
    /// "Re-apply preset after sleep/wake" setting and any active preview.
    private func forceApplyActive(state: AppState, controller: DDCController) {
        guard state.isSetUp else { return }
        guard state.applyOnWake else { return }
        guard state.previewingPresetID == nil else { return }

        controller.cliPath = state.cliPath
        controller.displayName = state.displayName

        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        lastAppliedEntryID = entry.id
        lastAppliedPreset = preset
        state.activePresetID = preset.id

        transitionTask?.cancel()
        transitionTask = Task {
            await controller.apply(preset)
        }
    }

    // MARK: - Tick

    private func tick(state: AppState, controller: DDCController) {
        // No verified monitor yet — nothing to drive until onboarding completes.
        guard state.isSetUp else { return }
        // Preview owns the monitor while active — don't fight it.
        guard state.previewingPresetID == nil else { return }

        controller.cliPath = state.cliPath
        controller.displayName = state.displayName

        guard let entry = activeEntry(in: state.schedule, presets: state.presets) else { return }
        guard let preset = state.preset(for: entry.presetID) else { return }

        if entry.id != lastAppliedEntryID {
            // Schedule moved to a new entry — smooth transition.
            let previous = lastAppliedPreset
            lastAppliedEntryID = entry.id
            lastAppliedPreset = preset
            state.activePresetID = preset.id

            transitionTask?.cancel()
            transitionTask = Task {
                if let from = previous {
                    await controller.applySmooth(from: from, to: preset, duration: 60)
                } else {
                    await controller.apply(preset)
                }
            }
        } else {
            switch controller.state(of: preset) {
            case .drifted:
                // Same entry, but the display genuinely drifted (wake from sleep,
                // reboot, BetterDisplay restart, manual override) — re-apply.
                transitionTask?.cancel()
                transitionTask = Task {
                    await controller.apply(preset)
                }
            case .matches, .unknown:
                // `.unknown` means the DDC read failed, which is not evidence of
                // drift. Re-applying on an unreadable display would fight the user
                // every tick for as long as reads keep failing; the next tick with
                // a working read corrects any real drift 15s later.
                break
            }
        }
    }

    // MARK: - Active entry logic

    /// Returns the most recent enabled schedule entry (pointing at an enabled preset) whose time ≤ now.
    /// Wraps midnight: if nothing is before now, returns the last entry of the day.
    private func activeEntry(in schedule: [ScheduleEntry], presets: [Preset]) -> ScheduleEntry? {
        let enabledPresetIDs = Set(presets.filter { $0.enabled }.map { $0.id })
        let enabled = schedule.filter { $0.enabled && enabledPresetIDs.contains($0.presetID) }
        guard !enabled.isEmpty else { return nil }

        let cal = Calendar.current
        let now = cal.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        if let entry = enabled.last(where: { $0.minutesSinceMidnight <= nowMinutes }) {
            return entry
        }
        return enabled.max(by: { $0.minutesSinceMidnight < $1.minutesSinceMidnight })
    }
}
