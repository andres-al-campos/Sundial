import Foundation
import IOKit

/// The bytes of DDC/CI, kept apart from the hardware so a test can check them.
enum DDCPacket {
    /// The display's address, the host's and the "set VCP feature" opcode, as DDC/CI defines them.
    static let displayAddress: UInt8 = 0x6E
    static let hostAddress: UInt8 = 0x51

    static func write(vcp: UInt8, value: UInt16) -> [UInt8] {
        var p: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        p[5] = checksum(p[0..<5])
        return p
    }

    static func readRequest(vcp: UInt8) -> [UInt8] {
        var p: [UInt8] = [0x82, 0x01, vcp, 0]
        p[3] = checksum(p[0..<3])
        return p
    }

    /// The current and maximum values in a "get VCP feature" reply, or nil when the reply isn't
    /// one: an empty answer is `6e 80 be`, which the M27Q sent when addressed at the wrong chip.
    static func parseReply(_ b: [UInt8], vcp: UInt8) -> (current: Int, max: Int)? {
        guard b.count >= 10, b[2] == 0x02, b[3] == 0, b[4] == vcp else { return nil }
        return (Int(b[8]) << 8 | Int(b[9]), Int(b[6]) << 8 | Int(b[7]))
    }

    /// The monitor's name from its EDID: the display descriptor tagged 0xFC.
    static func edidName(_ d: [UInt8]) -> String? {
        for off in [54, 72, 90, 108] where d.count >= off + 18 && d[off] == 0 && d[off + 1] == 0 && d[off + 3] == 0xFC {
            let name = String(decoding: d[(off + 5)..<(off + 18)], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            if !name.isEmpty { return name }
        }
        return nil
    }

    private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(displayAddress ^ hostAddress, ^)
    }
}

/// How DDC reaches a monitor. The app uses `IOAVLink`; a test can put a slow or recording one in
/// its place.
protocol DDCLink: Sendable {
    /// Whether any monitor whose name contains `display` took the value.
    func write(display: String, vcp: UInt8, value: UInt16) -> Bool
    func read(display: String, vcp: UInt8) -> (current: Int, max: Int)?
    /// The names of the external monitors connected now.
    func monitors() -> [String]
}

/// DDC over Apple silicon's IOAVService, the private interface MonitorControl, m1ddc and
/// BetterDisplay use too. Each call finds the monitor afresh: a service kept across sleep goes stale and takes
/// writes without passing them on (MonitorControl #530).
struct IOAVLink: DDCLink {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias I2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias CopyEDID = @convention(c) (CFTypeRef, UnsafeMutablePointer<Unmanaged<CFData>?>) -> IOReturn

    private struct Calls: @unchecked Sendable {
        let create: Create, writeI2C: I2C, readI2C: I2C, copyEDID: CopyEDID
    }

    private static let calls: Calls? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOAVServiceCreateWithService"), let w = dlsym(h, "IOAVServiceWriteI2C"),
              let r = dlsym(h, "IOAVServiceReadI2C"), let e = dlsym(h, "IOAVServiceCopyEDID") else {
            print("[Sundial] This macOS has no IOAVService, so Sundial can't set the monitor's brightness. Sundial needs a Mac with Apple silicon; please report the macOS version if it has one.")
            return nil
        }
        return Calls(create: unsafeBitCast(c, to: Create.self), writeI2C: unsafeBitCast(w, to: I2C.self),
                     readI2C: unsafeBitCast(r, to: I2C.self), copyEDID: unsafeBitCast(e, to: CopyEDID.self))
    }()

    /// The I2C address DDC/CI talks on, and the offset IOAVService wants for it.
    private static let address: UInt32 = 0x37
    /// A MacBook's or Mac mini's own HDMI port goes through an MCDP29xx converter, reached at
    /// 0xB7 instead. At 0x37 the M27Q on HDMI took every write without acting on it and answered
    /// every read empty (2026-11-05); m1ddc is where 0xB7 came from.
    private static let converterAddress: UInt32 = 0xB7
    private static let offset = UInt32(DDCPacket.hostAddress)

    private struct Monitor { let name: String; let av: CFTypeRef; let address: UInt32 }

    private func services() -> [Monitor] {
        guard let calls = Self.calls else { return [] }
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        var found: [Monitor] = []
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            let location = IORegistryEntryCreateCFProperty(s, "Location" as CFString, nil, 0)?.takeRetainedValue() as? String
            guard location == "External", let av = calls.create(nil, s)?.takeRetainedValue() else { continue }
            var edid: Unmanaged<CFData>?
            let name = calls.copyEDID(av, &edid) == 0
                ? (edid?.takeRetainedValue() as Data?).flatMap { DDCPacket.edidName([UInt8]($0)) }
                : nil
            found.append(Monitor(name: name ?? "", av: av, address: Self.behindConverter(s) ? Self.converterAddress : Self.address))
        }
        return found
    }

    private static func behindConverter(_ service: io_service_t) -> Bool {
        var parent = io_registry_entry_t()
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(parent) }
        let provider = IORegistryEntryCreateCFProperty(parent, "EPICProviderClass" as CFString, nil, 0)?.takeRetainedValue() as? String
        return provider == "AppleDCPMCDP29XX"
    }

    private func matching(_ display: String) -> [Monitor] {
        services().filter { $0.name.localizedCaseInsensitiveContains(display) }
    }

    func monitors() -> [String] { services().map(\.name).filter { !$0.isEmpty } }

    func write(display: String, vcp: UInt8, value: UInt16) -> Bool {
        guard let calls = Self.calls else { return false }
        var took = false
        for m in matching(display) {
            var p = DDCPacket.write(vcp: vcp, value: value)
            // Sent twice, as MonitorControl does: a monitor busy with the last value can drop one.
            for _ in 0..<2 {
                if calls.writeI2C(m.av, m.address, Self.offset, &p, UInt32(p.count)) == 0 { took = true }
                usleep(10_000)
            }
        }
        return took
    }

    func read(display: String, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let calls = Self.calls, let m = matching(display).first else { return nil }
        var req = DDCPacket.readRequest(vcp: vcp)
        for _ in 0..<2 {
            guard calls.writeI2C(m.av, m.address, Self.offset, &req, UInt32(req.count)) == 0 else { continue }
            // The converter answered empty after 10ms in m1ddc's testing; 50 works for both.
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            if calls.readI2C(m.av, m.address, Self.offset, &reply, UInt32(reply.count)) == 0,
               let value = DDCPacket.parseReply(reply, vcp: vcp) { return value }
        }
        return nil
    }
}
