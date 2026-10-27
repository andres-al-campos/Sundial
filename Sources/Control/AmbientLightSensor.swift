import Foundation
import IOKit

/// The MacBook's ambient light sensor: a photodiode beside the camera, not the
/// camera. It gives one number in lux, with no image, no camera light and no
/// permission prompt, and it runs with auto-brightness off.
///
/// Read through IOKit's HID event system, which is private API, the same way
/// `NightShiftController` uses CoreBrightness. A Mac without the sensor (a
/// desktop) or with the lid closed gives no reading, and Auto falls back to the
/// schedule.
///
/// A camera cover can sit over the sensor too: one read a flat 0 lux. Turned
/// round so it covered only the lens, the same cover read normally.
///
/// In the dark the lux level is whole numbers, so it reads 0 from a dim lamp
/// down to black. Below 10 lux the reading comes from a raw detector count
/// instead, which tells apart steps a tenth of a lux apart.
enum AmbientLightSensor {
    @_silgen_name("IOHIDEventSystemClientCreate")
    private static func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
    @_silgen_name("IOHIDEventSystemClientSetMatching")
    private static func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
    @_silgen_name("IOHIDEventSystemClientCopyServices")
    private static func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
    @_silgen_name("IOHIDServiceClientCopyEvent")
    private static func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
    @_silgen_name("IOHIDEventGetFloatValue")
    private static func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

    /// kIOHIDEventTypeAmbientLightSensor, its level field (type << 16) and the
    /// fourth field after it, a raw detector count.
    private static let eventType: Int64 = 12
    private static let levelField: Int32 = 12 << 16
    private static let rawField: Int32 = 12 << 16 | 4

    /// Below this the level is too coarse to use: it counts whole lux, so a
    /// dark room reads 0, 1 or 2. The raw count resolves about a tenth of a
    /// lux there.
    private static let fineBelowLux = 10.0
    /// Raw counts per lux, measured 2026-10-26 against an LED's six settings:
    /// 22 at 2 lux, 70 at 7, 112 at 12. Below about 0.1 lux both read 0.
    private static let countsPerLux = 10.0

    /// Apple vendor usage page, ambient light sensor usage. The client is kept
    /// with the service: the service doesn't keep its client alive, and reading
    /// it after the client is freed crashes on a freed lock inside IOKit (seen
    /// 2026-10-26, three crashes on the second read after launch).
    private static let sensor: (client: AnyObject, service: AnyObject)? = {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            print("[Sundial] Couldn't open the HID event system, so the room's light can't be read. Auto will follow the schedule instead.")
            return nil
        }
        _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject],
              let first = services.first else {
            print("[Sundial] No ambient light sensor found (Macs without a built-in display have none). Auto will follow the schedule instead.")
            return nil
        }
        return (client, first)
    }()

    /// The room's light in lux, or nil when there's no reading: no sensor, or
    /// the lid is closed.
    static func lux() -> Double? {
        guard !lidClosed() else { return nil }
        guard let sensor,
              let event = IOHIDServiceClientCopyEvent(sensor.service, eventType, 0, 0)?.takeRetainedValue() else { return nil }
        let level = IOHIDEventGetFloatValue(event, levelField)
        guard level < fineBelowLux else { return level }
        return IOHIDEventGetFloatValue(event, rawField) / countsPerLux
    }

    /// A closed lid covers the sensor, and its 0 lux would read as a dark room.
    private static func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
