import Foundation

/// A section of the desktop window.
enum WindowSection: String, CaseIterable, Identifiable {
    case presets, lights, settings
    var id: Self { self }
}

/// What can be asked of Sundial from outside it, as `sundial://` URLs
/// (`scripts/sundial` is the command-line way in). Pure, so tests/drive/remote.sh
/// can run it without the app.
enum RemoteCommand: Equatable {
    case status
    case pauseLights, resumeLights
    case auto, schedule
    case open(WindowSection?)
    case brightness(Int), contrast(Int)
    case readLights, loadLights, readHue, screenshot

    struct Failure: Error, Equatable { let message: String }

    static let usage = "Use status, pause, resume, auto, schedule, open [lights|presets|settings], brightness 0-100, contrast 0-100, lights, lights load <file>, hue or screenshot."

    static func parse(_ url: URL) -> Result<RemoteCommand, Failure> {
        guard url.scheme == "sundial", let host = url.host else {
            return .failure(Failure(message: "\"\(url.absoluteString)\" isn't a Sundial command. \(usage)"))
        }
        let rest = url.pathComponents.filter { $0 != "/" }
        switch (host, rest.first) {
        case ("status", nil): return .success(.status)
        case ("lights", "pause"): return .success(.pauseLights)
        case ("lights", "resume"): return .success(.resumeLights)
        case ("lights", "read"): return .success(.readLights)
        case ("lights", "load"): return .success(.loadLights)
        case ("hue", nil): return .success(.readHue)
        case ("screenshot", nil): return .success(.screenshot)
        case ("mode", "auto"): return .success(.auto)
        case ("mode", "schedule"): return .success(.schedule)
        case ("open", nil): return .success(.open(nil))
        case ("open", let name?):
            guard let section = WindowSection(rawValue: name) else {
                return .failure(Failure(message: "There's no section \"\(name)\". Use lights, presets or settings."))
            }
            return .success(.open(section))
        case ("brightness", let value?), ("contrast", let value?):
            guard let n = Int(value), (0...100).contains(n) else {
                return .failure(Failure(message: "\(host) takes a whole number from 0 to 100, not \"\(value)\"."))
            }
            return .success(host == "brightness" ? .brightness(n) : .contrast(n))
        default:
            return .failure(Failure(message: "\"\(url.absoluteString)\" isn't a Sundial command. \(usage)"))
        }
    }
}
