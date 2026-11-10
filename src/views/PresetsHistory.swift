import SwiftUI

/// Undo for the presets, one preset at a time: each change keeps that preset as it was, with its
/// times, so undoing it can't take back an edit made since to another one, from the popup say.
/// The bulbs' history keeps the whole setup instead (LightsHistory), since only the window edits it.
@MainActor
enum PresetsHistory {
    struct Slice: Equatable {
        var preset: Preset?
        var entries: [ScheduleEntry]
    }

    static func slice(_ id: UUID, in state: AppState) -> Slice {
        Slice(preset: state.preset(for: id), entries: state.schedule.filter { $0.presetID == id })
    }

    /// Does `change`, and if it changed the preset, keeps the version before it for undo. With
    /// `merging`, the same change again within a second joins the last undo, so a held arrow is one.
    static func change(_ id: UUID, _ name: String, in state: AppState, undo: UndoManager?,
                       merging: Bool = false, _ change: () -> Void) {
        let before = slice(id, in: state)
        change()
        guard slice(id, in: state) != before else { return }
        let now = Date()
        if merging, let last, last.id == id, last.name == name, now.timeIntervalSince(last.at) < 1 {
            self.last?.at = now
            return
        }
        last = merging ? (id, name, now) : nil
        register(id, before, name, in: state, undo: undo)
    }

    private static var last: (id: UUID, name: String, at: Date)?

    private static func register(_ id: UUID, _ version: Slice, _ name: String, in state: AppState, undo: UndoManager?) {
        guard let undo else { return }
        undo.registerUndo(withTarget: state) { state in
            MainActor.assumeIsolated {
                last = nil
                let current = slice(id, in: state)
                restore(id, version, in: state)
                register(id, current, name, in: state, undo: undo)
            }
        }
        undo.setActionName(name)
    }

    private static func restore(_ id: UUID, _ version: Slice, in state: AppState) {
        if let preset = version.preset {
            if let i = state.presets.firstIndex(where: { $0.id == id }) { state.presets[i] = preset } else { state.presets.append(preset) }
        } else {
            state.presets.removeAll { $0.id == id }
        }
        state.schedule.removeAll { $0.presetID == id }
        state.schedule.append(contentsOf: version.entries)
        state.schedule.sort { $0.minutesSinceMidnight < $1.minutesSinceMidnight }
        state.save()
        // The monitor follows the undo as it followed the edit: the preset being previewed shows
        // itself, anything else goes through the schedule.
        if let preset = version.preset, state.previewingPresetID == id {
            let controller = DDCController(displayName: state.displayName)
            Task { await controller.apply(preset) }
        } else {
            state.onScheduleChanged?()
        }
    }
}
