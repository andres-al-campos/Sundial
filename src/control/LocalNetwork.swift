import AppKit
import Network

/// Whether macOS is keeping Sundial off the local network. Once someone
/// declines the "find devices on your network" prompt, macOS never shows it
/// again: the only way back is the switch in System Settings.
enum LocalNetwork {
    /// True when reaching `host` (or, with no host yet, browsing for a Hue
    /// Bridge) is refused by the Local Network permission rather than failing
    /// for some other reason. False after `timeout` if neither answer comes.
    static func denied(host: String? = nil, timeout: TimeInterval = 3) async -> Bool {
        await withCheckedContinuation { c in
            let probe = Probe(c)
            let queue = DispatchQueue(label: "sundial.local-network")
            if let host {
                let conn = NWConnection(host: .init(host), port: 443, using: .tcp)
                probe.cancel = { conn.cancel() }
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready: probe.finish(false)
                    case .waiting(let e), .failed(let e):
                        probe.finish(conn.currentPath?.unsatisfiedReason == .localNetworkDenied || isPolicyDenied(e))
                    default: break
                    }
                }
                conn.start(queue: queue)
            } else {
                let browser = NWBrowser(for: .bonjour(type: "_hue._tcp", domain: "local."), using: .tcp)
                probe.cancel = { browser.cancel() }
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .waiting(let e), .failed(let e): probe.finish(isPolicyDenied(e))
                    default: break
                    }
                }
                // A bridge seen means the browse was allowed.
                browser.browseResultsChangedHandler = { results, _ in if !results.isEmpty { probe.finish(false) } }
                browser.start(queue: queue)
            }
            queue.asyncAfter(deadline: .now() + timeout) { probe.finish(false) }
        }
    }

    /// System Settings → Privacy & Security → Local Network.
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!)
    }

    private static func isPolicyDenied(_ e: NWError) -> Bool {
        if case .dns(let code) = e { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }

    /// Answers once, however many state changes and the timeout race to it.
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var c: CheckedContinuation<Bool, Never>?
        var cancel: () -> Void = {}
        init(_ c: CheckedContinuation<Bool, Never>) { self.c = c }
        func finish(_ denied: Bool) {
            lock.lock(); let c = self.c; self.c = nil; lock.unlock()
            guard let c else { return }
            cancel()
            c.resume(returning: denied)
        }
    }
}
