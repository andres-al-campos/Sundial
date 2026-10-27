import Foundation

struct ScheduleEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var presetID: UUID
    var hour: Int
    var minute: Int
    var enabled: Bool = true

    var timeString: String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        guard let date = Calendar.current.date(from: comps) else {
            return String(format: "%02d:%02d", hour, minute)
        }
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Minutes since midnight — used for sorting and comparison
    var minutesSinceMidnight: Int { hour * 60 + minute }
}
