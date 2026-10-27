import Foundation

/// Today's Night Shift schedule from the sun where you are, taken as the point
/// macOS's time zone table gives your time zone (America/Chicago is Chicago
/// itself). No location permission: each degree of longitude away from that
/// point moves the times about 4 minutes. Without a place (a zone like UTC),
/// the fitted fixed times.
enum SunClock {
    private static var cached: (key: String, schedule: RoomLight.WarmSchedule)?

    static func schedule(on date: Date = Date()) -> RoomLight.WarmSchedule {
        let zone = TimeZone.current
        let cal = Calendar.current
        let d = cal.dateComponents(in: zone, from: date)
        let key = "\(zone.identifier) \(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)"
        if let cached, cached.key == key { return cached.schedule }

        var sun: RoomLight.SunTimes?
        if let place = place(of: zone.identifier), let year = d.year, let month = d.month, let day = d.day {
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            sun = RoomLight.sunTimes(year: year, month: month, day: day,
                                     latitude: place.latitude, longitude: place.longitude,
                                     utcOffset: Double(zone.secondsFromGMT(for: noon)) / 3600)
        }
        let schedule = RoomLight.warmSchedule(sun: sun)
        cached = (key, schedule)
        return schedule
    }

    /// The time zone table's point for this zone, or nil when it isn't listed.
    private static func place(of identifier: String) -> (latitude: Double, longitude: Double)? {
        guard let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return nil }
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            if fields.count >= 3, fields[2] == identifier {
                return RoomLight.coordinates(iso6709: String(fields[1]))
            }
        }
        return nil
    }
}
