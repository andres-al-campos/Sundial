import AppKit

/// Carries out `sundial://` URLs. Each one writes status.json beside the config,
/// with the answer and what Sundial is doing, since a URL can't reply and
/// `scripts/sundial` has to print something.
@MainActor
enum RemoteControl {
    static func handle(_ url: URL, state: AppState) {
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        Task {
            switch RemoteCommand.parse(url) {
            case .success(let command):
                write(state, id: id, error: await run(command, state: state))
            case .failure(let failure):
                write(state, id: id, error: failure.message)
            }
        }
    }

    private static func file(_ name: String) -> URL { AppState.supportDirectory.appendingPathComponent(name) }

    /// Why it couldn't be done, or nil once it's done.
    private static func run(_ command: RemoteCommand, state: AppState) async -> String? {
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
        case .readLights:
            return store(state.lights ?? [], in: "lights.json")
        case .loadLights:
            return load(state)
        case .readHue:
            do {
                try await state.onReadHue?().write(to: file("hue.json"), options: .atomic)
                return nil
            } catch {
                return "Couldn't read the bridge: \(error.localizedDescription)"
            }
        case .screenshot:
            return screenshot()
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

    private static func store(_ bulbs: [LightDay.Bulb], in name: String) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(bulbs).write(to: file(name), options: .atomic)
            return nil
        } catch {
            return "Couldn't write \(name): \(error.localizedDescription). Check the disk has room, then try again."
        }
    }

    /// Replaces every bulb's day with lights-in.json, keeping what it replaces in
    /// lights-before-load.json, since Cmd-Z in the window doesn't reach past this.
    private static func load(_ state: AppState) -> String? {
        let bulbs: [LightDay.Bulb]
        do {
            bulbs = try JSONDecoder().decode([LightDay.Bulb].self, from: Data(contentsOf: file("lights-in.json")))
        } catch {
            return "Couldn't read that file as Sundial's lights: \(error.localizedDescription). Start from the output of `sundial lights`."
        }
        let current = state.lights ?? []
        if let problem = LightDay.problem(in: bulbs, knownIDs: Set(current.map(\.id))) { return problem }
        if let failed = store(current, in: "lights-before-load.json") { return failed }
        state.lights = bulbs
        state.save()
        state.onLampsChanged?()
        return nil
    }

    /// A picture of Sundial's own window, which needs no Screen Recording
    /// permission: that's for other apps' windows. `cacheDisplay` didn't do it,
    /// since it paints white under the views and leaves out dark mode's white text.
    private static func screenshot() -> String? {
        guard let window = NSApp.windows.first(where: { $0.title == "Sundial" && $0.isVisible }) else {
            return "Sundial's window isn't open. Run `sundial open`, then try again."
        }
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return "macOS wouldn't capture the window. Bring it on screen with `sundial open` and try again."
        }
        do {
            try png.write(to: file("screenshot.png"), options: .atomic)
            return nil
        } catch {
            return "Couldn't write the screenshot: \(error.localizedDescription). Check the disk has room, then try again."
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
        guard let state = Self.state else { return }
        MainActor.assumeIsolated {
            for url in urls { RemoteControl.handle(url, state: state) }
        }
    }
}
