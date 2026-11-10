import Foundation

/// Every change to a bulb's day, its color keys' brightness and color, one JSON line each, beside room-log.csv as lights-log.jsonl.
/// The room log has what the bulbs did each minute; this has the keys that made them do it, so the
/// light data can be read later against the keys in force: "log so we can come back and revisit".
/// The first line of a new log is every bulb as it stands, so the log starts from something.
enum LightsLog {
    static var url: URL { AppState.supportDirectory.appendingPathComponent("lights-log.jsonl") }

    struct Line: Codable {
        var time: String
        var change: String
        var bulb: String
        var keys: [LightDay.Key]
    }

    static func write(before: [LightDay.Bulb]?, after: [LightDay.Bulb]?, change: String) {
        let now = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        var lines: [Line] = []
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            lines += (before ?? []).map { Line(time: now, change: "Start of log", bulb: $0.name, keys: $0.keys) }
        }
        for bulb in after ?? [] where before?.first(where: { $0.id == bulb.id })?.keys != bulb.keys {
            lines.append(Line(time: now, change: change, bulb: bulb.name, keys: bulb.keys))
        }
        guard !lines.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = lines.compactMap { try? encoder.encode($0) }.reduce(into: Data()) { $0 += $1; $0 += Data("\n".utf8) }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
