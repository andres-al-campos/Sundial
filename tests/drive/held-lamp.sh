#!/bin/bash
# Drive: what a bulb is sent around a hold, from the real LampController and a stand-in bridge
# that records every call, so no real bulb moves. It runs in a home of its own, so the real
# config is untouched. It can't see the Lights window: it makes the calls the window makes.

set -euo pipefail
cd "$(dirname "$0")/../.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/HueBridge.swift" <<'SWIFT'
import Foundation

struct HueError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor enum Bulbs {
    static var now: [String: LightDay.State] = [:]
    static var fade: [String: TimeInterval] = [:]
}

final class HueBridge {
    struct Scene { var name: String; var lamps: [String: LampBlend.LampState] }
    struct Light { var id: String; var deviceID: String; var name: String }
    init(host: String, key: String?) {}
    var isPaired: Bool { true }
    static func discover(timeout: TimeInterval = 5) async -> String? { nil }
    static func savedKey(host: String) -> String? { "stand-in" }
    func pair(timeout: TimeInterval = 30) async throws {}
    func scenes() async throws -> [Scene] { [] }
    func lights() async throws -> [Light] { [Light(id: "a", deviceID: "da", name: "A"), Light(id: "b", deviceID: "db", name: "B")] }
    func scenesAsStored() async throws -> Data { Data() }
    func rename(device id: String, to name: String) async throws {}
    func lampsOn() async throws -> [String: Bool] {
        await MainActor.run { ["a": Bulbs.now["a"]?.on ?? true, "b": Bulbs.now["b"]?.on ?? true] }
    }
    func lampStates() async throws -> [String: LightDay.State] { await MainActor.run { Bulbs.now } }
    func set(lamp id: String, to state: LightDay.State, fade: TimeInterval, power: Bool = true) async throws {
        // A preview's send is slow here so one is still on its way when a drop's send goes out,
        // which on the real bridge is down to chance: answers took 50 to 250 ms.
        try await Task.sleep(for: .milliseconds(power ? 150 : 20))
        await MainActor.run {
            var landed = state
            if !power { landed.on = Bulbs.now[id]?.on ?? true }
            Bulbs.now[id] = landed
            Bulbs.fade[id] = fade
        }
    }
}
SWIFT

cat > "$work/main.swift" <<'SWIFT'
import Foundation

let hung = DispatchWorkItem { print("✗ held-lamp: the test hung. Something in LampController never finished."); exit(3) }
DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: hung)

typealias Look = LightDay.State
func look(_ b: Double, _ x: Double, _ y: Double) -> Look { .init(on: true, brightness: b, xy: .init(x: x, y: y)) }
let day = look(40, 0.50, 0.41), held = look(80, 0.20, 0.30), apart = look(60, 0.30, 0.60), dragged = look(10, 0.60, 0.35)
func named(_ s: Look?) -> String {
    guard let s else { return "nothing" }
    for (n, l) in [("the day", day), ("the hold", held), ("its own hold", apart), ("the dragged keyframe", dragged)]
    where abs(s.brightness - l.brightness) < 0.01 && abs(s.xy.x - l.xy.x) < 0.001 { return n }
    return "\(s)"
}

var failures: [String] = []
@MainActor func expect(_ what: String, _ want: [String: Look]) {
    for (id, l) in want.sorted(by: { $0.key < $1.key }) where named(Bulbs.now[id]) != named(l) {
        failures.append("\(what): bulb \(id) ended on \(named(Bulbs.now[id])), wanted \(named(l))")
    }
}
func settle() async { try? await Task.sleep(for: .milliseconds(700)) }

Task { @MainActor in
    let state = AppState()
    guard AppState.supportDirectory.path.contains("held-home") else {
        print("✗ held-lamp: the test would write to the real config at \(AppState.supportDirectory.path). Run it through this script, which gives it a home of its own."); exit(1)
    }
    func key(_ m: Int) -> LightDay.Key { .init(minute: m, anchor: nil, on: true, brightness: day.brightness, x: day.xy.x, y: day.xy.y) }
    var lead = LightDay.Bulb(id: "a", deviceID: "da", name: "A", keys: [key(0), key(720)])
    var follow = LightDay.Bulb(id: "b", deviceID: "db", name: "B", keys: [])
    follow.parent = lead.id
    lead.name = "A"
    state.lights = [lead, follow]
    state.hueHost = "stand-in"
    state.lampsFollow = true
    let lamps = LampController()
    state.onLampsChanged = { lamps.refresh() }
    lamps.start(state: state)
    await settle()
    expect("at first", ["a": day, "b": day])

    // Each is what LightsView calls. A drop saves, which refreshes, and then ends the preview.
    @MainActor func drag(show: Look = dragged) async {
        lamps.preview(["a": show, "b": show])
        try? await Task.sleep(for: .milliseconds(450))
        expect("during a drag", ["a": show, "b": show])
        // Let go with the last move's send still on its way.
        lamps.preview(["a": show, "b": show])
        try? await Task.sleep(for: .milliseconds(120))
        state.onLampsChanged?()
        lamps.endPreview()
        await settle()
    }

    await drag()
    expect("a drag with no hold", ["a": day, "b": day])

    var off = dragged
    off.on = false
    await drag(show: off)
    expect("a drag of an off keyframe", ["a": day, "b": day])
    if Bulbs.now["a"]?.on != true { failures.append("a drag of an off keyframe: bulb a stayed off. Only someone switching it off keeps it off, and a preview isn't that.") }

    let until = Date().addingTimeInterval(3600)
    state.holds["a"] = .init(look: held, until: until)
    lamps.preview(["a": held, "b": held])
    lamps.endPreview()
    await settle()
    expect("holding the bulb followed", ["a": held, "b": held])

    await drag()
    expect("a drag while held", ["a": held, "b": held])
    if Bulbs.fade["a"] != LampController.returnFade {
        failures.append("a drag while held: the way back took \(Bulbs.fade["a"] ?? 0)s, not the quick \(LampController.returnFade)s. A preview left to the usual fade looks stuck.")
    }

    state.holds["b"] = .init(look: apart, until: until)
    lamps.preview(["b": apart])
    lamps.endPreview()
    await settle()
    await drag()
    expect("a drag with the follower held apart", ["a": held, "b": apart])

    state.holds = [:]
    lamps.endPreview()
    await settle()
    expect("back to schedule", ["a": day, "b": day])

    state.holds["a"] = .init(look: held, until: until)
    lamps.preview(["a": held, "b": held])
    lamps.endPreview()
    await settle()
    state.lampsFollow = false
    await drag()
    expect("a drag while held and paused", ["a": held, "b": held])

    // Paused is when the Hue app may have them doing anything, and the room log still wants to know.
    // A look bulb a has had at no earlier read, so a stale read can't pass for this one.
    Bulbs.now["a"] = apart
    lamps.refresh()
    await settle()
    if named(state.lampsRead["a"]) != named(apart) {
        failures.append("the room log's read while paused: bulb a read \(named(state.lampsRead["a"])), wanted what it's doing now. Read the lamps above the pause guard in tick.")
    }

    hung.cancel()
    if failures.isEmpty { exit(0) }
    print("✗ held-lamp: a bulb ended on the wrong look. Fix it in src/control/LampController.swift, where a preview hands back (endPreview, tick, restore):")
    failures.forEach { print("    \($0)") }
    exit(1)
}
RunLoop.main.run()
SWIFT

sources=$(find src -name '*.swift' ! -name SundialApp.swift ! -name HueBridge.swift ! -name RemoteControl.swift ! -path 'src/views/*')
# shellcheck disable=SC2086
if ! swiftc -target arm64-apple-macos14 -o "$work/held-lamp" "$work/main.swift" "$work/HueBridge.swift" $sources 2> "$work/err"; then
    echo "✗ held-lamp: the harness didn't compile. The stand-in in tests/drive/held-lamp.sh has to offer what src/control/HueBridge.swift does:"
    grep "error:" "$work/err" | sed 's/^/    /' | head -20
    exit 1
fi
mkdir -p "$work/held-home"
CFFIXED_USER_HOME="$work/held-home" "$work/held-lamp"
echo "✓ held-lamp: a bulb under a hold goes back to the hold after a drag, quickly, followers too, and back to the day once it ends"
