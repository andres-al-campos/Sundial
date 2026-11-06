#!/bin/bash
# Law: the DDC/CI bytes Sundial sends and reads are the ones the standard defines.
#
# Checked against packets worked out by hand from the VESA DDC/CI layout and a reply the M27Q
# really sent, so a change to DDCPacket can't quietly send a monitor bytes it ignores.

set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures: [String] = []
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func expect(_ got: [UInt8], _ want: [UInt8], _ what: String) {
    if got != want { failures.append("\(what) is \(hex(got)), wanted \(hex(want)).") }
}
expect(DDCPacket.write(vcp: 0x10, value: 50), [0x84, 0x03, 0x10, 0x00, 0x32, 0x9a], "setting brightness to 50")
expect(DDCPacket.write(vcp: 0x12, value: 0x0123), [0x84, 0x03, 0x12, 0x01, 0x23, 0x88], "setting contrast to 0x123")
expect(DDCPacket.readRequest(vcp: 0x10), [0x82, 0x01, 0x10, 0xac], "asking for brightness")

// The M27Q's answer with its brightness at 2, on 2026-11-05.
let reply: [UInt8] = [0x6e, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x02, 0xc2, 0x00]
if let r = DDCPacket.parseReply(reply, vcp: 0x10), r.current == 2, r.max == 100 {} else {
    failures.append("the M27Q's brightness reply of 2 out of 100 parsed as \(String(describing: DDCPacket.parseReply(reply, vcp: 0x10))).")
}
if DDCPacket.parseReply(reply, vcp: 0x12) != nil { failures.append("a brightness reply was taken as contrast's.") }
let silent: [UInt8] = [0x6e, 0x80, 0xbe] + [UInt8](repeating: 0, count: 9)
if DDCPacket.parseReply(silent, vcp: 0x10) != nil { failures.append("an empty reply (6e 80 be) was taken as a value.") }

var edid = [UInt8](repeating: 0, count: 128)
edid[72...76] = [0, 0, 0, 0xFC, 0]
edid[77..<90] = ArraySlice(Array("M27Q\n        ".utf8))
if DDCPacket.edidName(edid) != "M27Q" { failures.append("the EDID name read as \(String(describing: DDCPacket.edidName(edid))), wanted M27Q.") }

if failures.isEmpty { exit(0) }
print("✗ ddc-packets: DDCPacket in src/control/DDC.swift builds or reads DDC/CI bytes wrong. Each packet is opcode, length, VCP code, value, then a checksum XORing 0x6E, 0x51 and every byte before it:")
failures.forEach { print("    \($0)") }
exit(1)
SWIFT

if ! swiftc -target arm64-apple-macos14 -o "$work/t" "$work/main.swift" src/control/DDC.swift 2> "$work/err"; then
    echo "✗ ddc-packets: the test didn't compile. Update tests/ddc-packets.sh to match src/control/DDC.swift:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
"$work/t"
echo "✓ ddc-packets: write, read-request, reply and EDID-name bytes match DDC/CI"
