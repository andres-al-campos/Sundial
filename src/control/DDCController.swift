import Foundation

@MainActor
class DDCController {
    var displayName: String

    init(displayName: String) {
        self.displayName = displayName
    }

    // MARK: - Public API

    func apply(_ preset: Preset) async {
        await setPercent("hardwareBrightness", value: preset.hardwareBrightness)
        await setPercent("hardwareContrast", value: preset.hardwareContrast)
        NightShiftController.setStrength(preset.nightShift)
    }

    /// Apply only a single parameter — used during live slider drag to avoid
    /// re-sending unchanged params.
    func applySingle(_ param: String, value: Int) async {
        if param == "nightShift" {
            NightShiftController.setStrength(value)
        } else {
            await setPercent(param, value: value)
        }
    }

    /// Smoothly interpolate from `from` to `to` over `duration` seconds.
    /// Cancellable — callers should wrap in a Task.
    func applySmooth(from: Preset, to: Preset, duration: TimeInterval = 60) async {
        let stepInterval: TimeInterval = 2.0
        let steps = max(1, Int(duration / stepInterval))

        for step in 1...steps {
            guard !Task.isCancelled else { return }
            let t = Double(step) / Double(steps)
            await apply(from.lerp(to: to, t: t))
            if step < steps {
                try? await Task.sleep(nanoseconds: UInt64(stepInterval * 1_000_000_000))
            }
        }
    }

    /// How the display's actual DDC state compares to a preset.
    ///
    /// `.unknown` is deliberately distinct from `.drifted`: a failed DDC read is
    /// not evidence that anything moved. Collapsing the two makes an unreachable
    /// or flaky monitor look permanently drifted, so the scheduler re-applies on
    /// every tick and the user can never change anything by hand.
    enum DisplayState {
        case matches
        case drifted
        case unknown
    }

    /// Compare the display's actual DDC brightness and contrast against a preset.
    /// Returns `.unknown` if either read fails — see `DisplayState`.
    func state(of preset: Preset) async -> DisplayState {
        guard let brightness = await readDDC(vcp: 0x10),
              let contrast   = await readDDC(vcp: 0x12) else { return .unknown }
        let ok = abs(brightness - preset.hardwareBrightness) <= 1
              && abs(contrast   - preset.hardwareContrast)   <= 1
        return ok ? .matches : .drifted
    }

    /// Whether a connected monitor goes by the configured name. Setup asks this
    /// rather than for a read, since some monitors take DDC writes but never
    /// answer reads.
    func probe() async -> Bool {
        let name = displayName
        return await Self.monitors().contains { $0.localizedCaseInsensitiveContains(name) }
    }

    // MARK: - Private

    private func readDDC(vcp: UInt8) async -> Int? {
        let name = displayName
        let value = await Self.onQueue { Self.link.read(display: name, vcp: vcp) }
        guard let value else {
            // Once per monitor: the drift check reads every minute, and a monitor that never
            // answers would fill the log.
            guard Self.unanswered.insert(name).inserted else { return nil }
            print(String(format: "[Sundial] The monitor \"%@\" didn't answer a DDC read of 0x%02X. Check that DDC/CI is on in its on-screen menu; some monitors never answer reads, and Sundial then can't tell when the screen was changed by hand.", name, vcp))
            return nil
        }
        return value.max > 0 ? Int((Double(value.current) / Double(value.max) * 100).rounded()) : value.current
    }

    private func setPercent(_ param: String, value: Int) async {
        guard let vcp = Self.codes[param] else { return }
        let name = displayName
        let took = await Self.onQueue { () -> Bool in
            let raw = UInt16(max(0, min(100, value)) * Self.maximum(display: name, vcp: vcp) / 100)
            return Self.link.write(display: name, vcp: vcp, value: raw)
        }
        if !took {
            print("[Sundial] Couldn't set \(param) to \(value)% on \"\(name)\": no connected monitor by that name took it. Check the monitor name in Settings against the connected ones (\(await Self.monitors().joined(separator: ", "))), and that DDC/CI is on in the monitor's on-screen menu.")
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    private static var unanswered: Set<String> = []

    private static let codes: [String: UInt8] = ["hardwareBrightness": 0x10, "hardwareContrast": 0x12]

    /// The transport. A test swaps in its own before anything is sent.
    nonisolated(unsafe) static var link: any DDCLink = IOAVLink()

    /// The names of the external monitors connected now, for setup to offer.
    static func monitors() async -> [String] { await onQueue { link.monitors() } }

    /// Each monitor's top value per control, read once. Most monitors say 100; one that doesn't
    /// answer reads is taken to mean 100 too.
    nonisolated(unsafe) private static var maxima: [String: Int] = [:]

    private nonisolated static func maximum(display: String, vcp: UInt8) -> Int {
        let key = "\(display)/\(vcp)"
        if let known = maxima[key] { return known }
        let found = link.read(display: display, vcp: vcp)?.max ?? 0
        let top = found > 0 ? found : 100
        maxima[key] = top
        return top
    }

    /// Every call goes through one queue, in the order they were made, so a drag's values land in
    /// the order they were dragged. Off the main thread: a monitor slow to answer over I2C would
    /// otherwise freeze the app, as a slow BetterDisplay once did.
    private nonisolated static let queue = DispatchQueue(label: "com.aurende.sundial.ddc")

    private nonisolated static func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in
            queue.async { done.resume(returning: work()) }
        }
    }
}
