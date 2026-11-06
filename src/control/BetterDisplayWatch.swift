import AppKit

/// Whether BetterDisplay's own app is open. Sundial sets the monitor through its command line,
/// which with the app closed starts a copy of it per command that takes about 16 seconds, so the
/// popup says so rather than leaving the screen lagging with no reason given.
@MainActor
final class BetterDisplayWatch {
    static let bundleID = "pro.betterdisplay.BetterDisplay"
    private var observers: [NSObjectProtocol] = []

    /// `back` runs when the app opens after being closed, so the monitor catches up at once.
    func start(state: AppState, back: @escaping () -> Void) {
        state.betterDisplayOpen = Self.isOpen()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak state] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated {
                    guard let state else { return }
                    let was = state.betterDisplayOpen
                    state.betterDisplayOpen = Self.isOpen()
                    if !was, state.betterDisplayOpen { back() }
                }
            })
        }
    }

    /// The copies Sundial's own commands start are BetterDisplay too, so only one Sundial didn't
    /// start counts.
    nonisolated static func isOpen() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated && parent(of: $0.processIdentifier) != getpid() }
    }

    nonisolated static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private nonisolated static func parent(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }
}
