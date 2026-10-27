import Foundation

@MainActor
class DDCController {
    var cliPath: String
    var displayName: String

    init(cliPath: String, displayName: String) {
        self.cliPath = cliPath
        self.displayName = displayName
    }

    // MARK: - Public API

    func apply(_ preset: Preset) async {
        await setPercent("hardwareBrightness", value: preset.hardwareBrightness)
        await setPercent("hardwareContrast", value: preset.hardwareContrast)
        NightShiftController.setStrength(preset.nightShift)
    }

    /// Apply only a single parameter — used during live slider drag to avoid
    /// re-sending unchanged params and triggering BetterDisplay's poll/snap.
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
    /// Uses raw DDC reads (VCP codes) to bypass BetterDisplay's cache. Returns
    /// `.unknown` if either read fails — see `DisplayState`.
    func state(of preset: Preset) -> DisplayState {
        guard let brightness = readDDC(vcp: 0x10),
              let contrast   = readDDC(vcp: 0x12) else { return .unknown }
        let ok = abs(brightness - preset.hardwareBrightness) <= 1
              && abs(contrast   - preset.hardwareContrast)   <= 1
        return ok ? .matches : .drifted
    }

    /// Probe whether the configured display is reachable over DDC by attempting
    /// a raw brightness read (VCP 0x10). Used by setup validation to confirm the
    /// CLI path + display name resolve to a real, controllable monitor before
    /// unlocking presets. Returns true if the read returns a value.
    func probe() async -> Bool {
        readDDC(vcp: 0x10) != nil
    }

    // MARK: - Private

    /// Read a raw DDC value from the monitor via VCP code. Returns the integer
    /// value directly from the display hardware, bypassing BetterDisplay's cache.
    /// VCP 0x10 = brightness, 0x12 = contrast.
    private func readDDC(vcp: Int) -> Int? {
        let hex = String(format: "0x%02X", vcp)
        let result = runCapture([cliPath, "get", "-nameLike=\(displayName)", "-ddc", "-vcp=\(hex)"])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) { return value }

        // Read failed. Say why — the caller only sees nil, so this is the one
        // place the actual reason is available.
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        switch result.outcome {
        case .timedOut:
            print("[Sundial] DDC read of \(hex) timed out after \(Self.commandTimeout)s. BetterDisplay may be busy or wedged — quit and reopen BetterDisplay if this persists.")
        case .launchFailed(let message):
            print("[Sundial] Could not launch BetterDisplay: \(message) — verify the path in Settings points to /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay and that BetterDisplay.app is installed.")
        case .exited(let status):
            var detail = "[Sundial] DDC read of \(hex) from \"\(displayName)\" failed"
            if status != 0 { detail += " (exit \(status))" }
            if !trimmed.isEmpty { detail += ": \(trimmed)" }
            if !stderr.isEmpty { detail += " / \(stderr)" }
            print(detail)
            print("[Sundial] The monitor may not support DDC reads, may have DDC/CI disabled in its on-screen menu, or the display name in Settings may not match a connected monitor.")
        }
        return nil
    }

    private func setPercent(_ param: String, value: Int) async {
        run([cliPath, "set", "-namelike=\(displayName)", "-\(param)=\(value)%"])
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    /// Seconds to wait for a CLI invocation before giving up. BetterDisplay can
    /// hang indefinitely (observed on `version` and on DDC reads to a wedged
    /// monitor); `waitUntilExit()` would block the caller forever if it does.
    static let commandTimeout: TimeInterval = 5

    private struct CaptureResult {
        enum Outcome {
            case exited(Int32)
            case timedOut
            case launchFailed(String)
        }
        var outcome: Outcome
        var stdout: String
        var stderr: String
    }

    private func runCapture(_ args: [String]) -> CaptureResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CaptureResult(outcome: .launchFailed(error.localizedDescription), stdout: "", stderr: "")
        }

        // Drain both pipes on background queues. A process that fills a pipe
        // buffer blocks until it is read, so reading only after waiting would
        // deadlock on verbose output.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(Self.commandTimeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                // SIGTERM may not land; give it a moment, then SIGKILL so the
                // pipe readers get EOF and the group can complete.
                if group.wait(timeout: .now() + 0.5) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                }
                timedOut = true
                break
            }
            usleep(20_000)
        }

        _ = group.wait(timeout: .now() + 1.0)
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        let outcome: CaptureResult.Outcome = timedOut ? .timedOut : .exited(process.terminationStatus)
        return CaptureResult(outcome: outcome, stdout: stdout, stderr: stderr)
    }

    @discardableResult
    private func run(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            if status != 0 {
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let cmd = args.joined(separator: " ")
                print("[Sundial] CLI exited \(status) for: \(cmd)")
                if !out.isEmpty { print("[Sundial] stdout: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if !err.isEmpty { print("[Sundial] stderr: \(err.trimmingCharacters(in: .whitespacesAndNewlines))") }
                if out.contains("Failed") || err.contains("Failed") {
                    print("[Sundial] BetterDisplay reported 'Failed' — the display name in Settings may not match any connected monitor. Check Settings → Display name and confirm it matches (partial match) the monitor name shown in BetterDisplay.")
                }
            }
            return status
        } catch {
            print("[Sundial] Could not launch BetterDisplay: \(error.localizedDescription) — verify the path in Settings points to /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay and that BetterDisplay.app is installed.")
            return -1
        }
    }
}
