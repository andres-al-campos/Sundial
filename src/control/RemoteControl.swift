import AppKit

/// Carries out `sundial://` URLs. Each one writes status.json beside the config,
/// with the answer and what Sundial is doing, since a URL can't reply and
/// `scripts/sundial` has to print something.
@MainActor
enum RemoteControl {
    static func handle(_ url: URL, state: AppState) {
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        switch RemoteCommand.parse(url) {
        case .success(let command):
            write(state, id: id, error: run(command, state: state))
        case .failure(let failure):
            write(state, id: id, error: failure.message)
        }
    }

    /// Why it couldn't be done, or nil once it's done.
    private static func run(_ command: RemoteCommand, state: AppState) -> String? {
        switch command {
        case .status:
            return nil
        case .pauseLights, .resumeLights:
            guard state.hueHost != nil else {
                return "Sundial isn't paired with a Hue Bridge. Run `sundial open settings` and pair it."
            }
            state.lampsFollow = command == .resumeLights
            state.save()
            state.onLampsChanged?()
            return nil
        case .auto:
            state.setMode(.auto)
            return nil
        case .schedule:
            state.setMode(.schedule)
            return nil
        case .open(let section):
            if let section { state.windowSection = section }
            MainWindow.show(state)
            return nil
        case .brightness(let n):
            guard state.mode == .auto else { return scheduleOwns("Brightness") }
            state.onSetBrightness?(n, true)
            return nil
        case .contrast(let n):
            guard state.mode == .auto else { return scheduleOwns("Contrast") }
            state.onSetContrast?(n, true)
            return nil
        }
    }

    private static func scheduleOwns(_ what: String) -> String {
        "\(what) comes from the current preset in Schedule mode. Run `sundial auto` first, or edit the preset with `sundial open presets`."
    }

    private static func write(_ state: AppState, id: String?, error: String?) {
        var status: [String: Any] = [
            "ok": error == nil,
            "mode": state.mode.rawValue,
            "brightness": state.autoBrightness,
            "contrast": state.autoContrast,
            "nightShift": state.autoNightShift,
            "lightsFollowing": state.lampsFollow,
            "lights": state.lampStatus,
        ]
        status["id"] = id
        status["error"] = error
        status["roomLux"] = state.sensorReading ? state.roomLux : nil
        if state.mode == .schedule { status["preset"] = state.preset(for: state.activePresetID)?.name }
        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: AppState.supportDirectory.appendingPathComponent("status.json"), options: .atomic)
    }
}

/// Opens `sundial://` URLs. A SwiftUI `onOpenURL` would need the popup to have
/// been opened first, and these have to work with it shut.
final class SundialAppDelegate: NSObject, NSApplicationDelegate {
    static var state: AppState?

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard let state = Self.state else { return }
            for url in urls { RemoteControl.handle(url, state: state) }
        }
    }
}
