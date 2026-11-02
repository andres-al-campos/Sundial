import Foundation

/// Today's Night Shift schedule from the sun where you are, taken as the point
/// macOS's time zone table gives your time zone (America/Chicago is Chicago
/// itself). No location permission: each degree of longitude away from that
/// point moves the times about 4 minutes. Without a place (a zone like UTC),
/// the fitted fixed times. A place picked in Settings stands in for that point
/// while the Mac stays in the time zone it was picked in.
enum SunClock {
    private static var cached: (key: String, sun: RoomLight.SunTimes?)?
    /// Set by `AppState`, which holds it.
    static var picked: RoomLight.Place?

    static func schedule(on date: Date = Date(), bedtime: Int) -> RoomLight.WarmSchedule {
        RoomLight.warmSchedule(sun: sun(on: date), bedtime: bedtime)
    }

    /// Today's sunrise and sunset, or nil without a place for the time zone.
    static func sun(on date: Date = Date()) -> RoomLight.SunTimes? {
        // Autoupdating, so a time zone change while traveling is seen at once.
        let zone = TimeZone.autoupdatingCurrent
        let cal = Calendar.autoupdatingCurrent
        let d = cal.dateComponents(in: zone, from: date)
        let place = location(in: zone)
        let key = "\(zone.identifier) \(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0) \(place.map { "\($0.latitude),\($0.longitude)" } ?? "")"
        if let cached, cached.key == key { return cached.sun }

        var sun: RoomLight.SunTimes?
        if let place, let year = d.year, let month = d.month, let day = d.day {
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            sun = RoomLight.sunTimes(year: year, month: month, day: day,
                                     latitude: place.latitude, longitude: place.longitude,
                                     utcOffset: Double(zone.secondsFromGMT(for: noon)) / 3600)
        }
        cached = (key, sun)
        return sun
    }

    /// Where the sun is worked out for: the picked place if it's still in this time
    /// zone, otherwise the time zone table's point.
    static func location(in zone: TimeZone = .autoupdatingCurrent) -> (latitude: Double, longitude: Double)? {
        if let picked, picked.zone == zone.identifier {
            return (Double(picked.latitude), Double(picked.longitude))
        }
        return place(of: zone.identifier)
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
