import Foundation
import Security

/// The Hue Bridge on the local network, over its own API (CLIP v2). Needs the
/// home network, not the internet.
final class HueBridge: NSObject, URLSessionDelegate {
    let host: String
    private var key: String?
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(host: String, key: String?) {
        self.host = host
        self.key = key
    }

    var isPaired: Bool { key != nil }

    // MARK: - Finding and pairing

    /// The first bridge Bonjour finds (`_hue._tcp`), as a host name, or nil
    /// after `timeout` seconds.
    @MainActor
    static func discover(timeout: TimeInterval = 5) async -> String? {
        await Finder().find(timeout: timeout)
    }

    /// Ask for a key until the bridge's link button has been pressed, for up to
    /// `timeout` seconds (the bridge allows 30 after a press). Saves it in the
    /// Keychain.
    func pair(timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var req = URLRequest(url: URL(string: "https://\(host)/api")!)
            req.httpMethod = "POST"
            req.httpBody = Data(#"{"devicetype":"sundial#mac"}"#.utf8)
            if let (data, _) = try? await session.data(for: req),
               let reply = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let user = (reply.first?["success"] as? [String: Any])?["username"] as? String {
                key = user
                Self.saveKey(user, host: host)
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw HueError("The bridge didn't answer with a key. Press the round button on top of the bridge, then pair again within 30 seconds.")
    }

    // MARK: - Reading and setting

    struct Scene { var name: String; var lamps: [String: LampBlend.LampState] }

    func scenes() async throws -> [Scene] {
        let data = try await get("scene")
        return data.compactMap { s in
            guard let name = (s["metadata"] as? [String: Any])?["name"] as? String,
                  let actions = s["actions"] as? [[String: Any]] else { return nil }
            var lamps: [String: LampBlend.LampState] = [:]
            for a in actions {
                guard let id = (a["target"] as? [String: Any])?["rid"] as? String,
                      let act = a["action"] as? [String: Any] else { continue }
                let b = ((act["dimming"] as? [String: Any])?["brightness"] as? Double)
                    ?? (((act["on"] as? [String: Any])?["on"] as? Bool) == true ? 100 : nil)
                let xy: LampBlend.XY?
                if let c = (act["color"] as? [String: Any])?["xy"] as? [String: Any],
                   let x = c["x"] as? Double, let y = c["y"] as? Double {
                    xy = .init(x: x, y: y)
                } else if let m = (act["color_temperature"] as? [String: Any])?["mirek"] as? Double {
                    xy = LampBlend.xy(mirek: m)
                } else {
                    xy = nil
                }
                if let b, let xy { lamps[id] = .init(brightness: b, xy: xy) }
            }
            return Scene(name: name, lamps: lamps)
        }
    }

    struct Light { var id: String; var deviceID: String; var name: String }

    /// The bulbs on the bridge. The name lives on the device, not the light.
    func lights() async throws -> [Light] {
        let names = Dictionary(try await get("device").compactMap { d -> (String, String)? in
            guard let id = d["id"] as? String, let name = (d["metadata"] as? [String: Any])?["name"] as? String else { return nil }
            return (id, name)
        }, uniquingKeysWith: { a, _ in a })
        return try await get("light").compactMap { l in
            guard let id = l["id"] as? String, let device = (l["owner"] as? [String: Any])?["rid"] as? String else { return nil }
            return Light(id: id, deviceID: device, name: names[device] ?? "Bulb")
        }
    }

    /// The bridge's scenes and its Natural-light style schedules, as it holds them.
    func scenesAsStored() async throws -> Data {
        let all: [String: Any] = ["scene": try await get("scene"), "smart_scene": try await get("smart_scene"),
                                  "behavior_instance": try await get("behavior_instance")]
        return try JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys])
    }

    func rename(device id: String, to name: String) async throws {
        var req = try request("device/\(id)")
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["metadata": ["name": name]])
        let (data, resp) = try await fetch(req)
        try check(resp, data)
    }

    /// Which lamps are lit right now, by light id.
    func lampsOn() async throws -> [String: Bool] {
        var lit: [String: Bool] = [:]
        for l in try await get("light") {
            if let id = l["id"] as? String, let on = (l["on"] as? [String: Any])?["on"] as? Bool { lit[id] = on }
        }
        return lit
    }

    /// Each lamp as it is now, to put back after a preview while paused.
    func lampStates() async throws -> [String: LightDay.State] {
        var states: [String: LightDay.State] = [:]
        for l in try await get("light") {
            guard let id = l["id"] as? String, let on = (l["on"] as? [String: Any])?["on"] as? Bool,
                  let brightness = (l["dimming"] as? [String: Any])?["brightness"] as? Double,
                  let xy = ((l["color"] as? [String: Any])?["xy"]) as? [String: Any],
                  let x = xy["x"] as? Double, let y = xy["y"] as? Double else { continue }
            states[id] = LightDay.State(on: on, brightness: brightness, xy: .init(x: x, y: y))
        }
        return states
    }

    /// Fade a lamp to `state` over `fade` seconds. Off sends only that: the bulb
    /// keeps its brightness and colour for when it's next on. Without `power` the
    /// lamp's on or off stays as it is, so a lamp switched off just after
    /// `lampsOn` read it doesn't come back on.
    func set(lamp id: String, to state: LightDay.State, fade: TimeInterval, power: Bool = true) async throws {
        var body: [String: Any] = ["dynamics": ["duration": Int(fade * 1000)]]
        if power { body["on"] = ["on": state.on] }
        if state.on {
            body["dimming"] = ["brightness": state.brightness]
            body["color"] = ["xy": ["x": state.xy.x, "y": state.xy.y]]
        }
        var req = try request("light/\(id)")
        req.httpMethod = "PUT"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await fetch(req)
        try check(resp, data)
    }

    private func get(_ resource: String) async throws -> [[String: Any]] {
        let (data, resp) = try await fetch(try request(resource))
        try check(resp, data)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [[String: Any]] ?? []
    }

    private func request(_ resource: String) throws -> URLRequest {
        guard let key else { throw HueError("Sundial isn't paired with the bridge. Open Settings → Lamps and pair it.") }
        var req = URLRequest(url: URL(string: "https://\(host)/clip/v2/resource/\(resource)")!, timeoutInterval: 5)
        req.setValue(key, forHTTPHeaderField: "hue-application-key")
        return req
    }

    /// A request whose network failures say what to do. macOS reports a
    /// declined Local Network permission as an ordinary lookup failure, so a
    /// failed request asks the Network framework whether that's the cause.
    private func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: req) }
        catch let e as URLError where [.cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
                                       .timedOut, .networkConnectionLost, .notConnectedToInternet].contains(e.code) {
            if await LocalNetwork.denied(host: host) { throw HueError.localNetworkDenied }
            throw HueError("Sundial can't reach the Hue Bridge (\(e.localizedDescription)). Check the bridge is plugged in and this Mac is on the same network as it, then try again.")
        }
    }

    private func check(_ resp: URLResponse, _ data: Data) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 {
            key = nil
            Self.deleteKey(host: host)
            throw HueError("The bridge no longer accepts Sundial's key (it was removed in the Hue app, or the bridge was reset). Open Settings → Lamps and pair again.")
        }
        guard (200..<300).contains(code) else {
            throw HueError("The bridge answered \(code): \(String(decoding: data.prefix(200), as: UTF8.self)). Check the bridge is on and reachable, then try again.")
        }
    }

    /// The bridge's certificate is signed by Signify's own root, not one macOS
    /// trusts, so it's accepted for the bridge's host and nothing else.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == host, let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Keychain

    private static let service = "com.aurende.sundial.hue"

    static func savedKey(host: String) -> KeychainRead {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: host, kSecReturnData as String: true]
        var out: AnyObject?
        switch SecItemCopyMatching(q as CFDictionary, &out) {
        case errSecSuccess:
            guard let d = out as? Data else { return .missing }
            return .found(String(decoding: d, as: UTF8.self))
        case errSecItemNotFound: return .missing
        // Deny, closing the prompt, or a locked Keychain: the key is there, Sundial just wasn't let in.
        default: return .declined
        }
    }

    private static func saveKey(_ key: String, host: String) {
        deleteKey(host: host)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: host, kSecValueData as String: Data(key.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func deleteKey(host: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: host]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: - Bonjour

    @MainActor
    private final class Finder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
        private let browser = NetServiceBrowser()
        private var services: [NetService] = []
        private var done: CheckedContinuation<String?, Never>?

        func find(timeout: TimeInterval) async -> String? {
            await withCheckedContinuation { c in
                done = c
                browser.delegate = self
                browser.searchForServices(ofType: "_hue._tcp.", inDomain: "local.")
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(nil) }
            }
        }

        private func finish(_ host: String?) {
            browser.stop()
            done?.resume(returning: host)
            done = nil
        }

        nonisolated func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
            MainActor.assumeIsolated {
                services.append(s)
                s.delegate = self
                s.resolve(withTimeout: 5)
            }
        }

        nonisolated func netServiceDidResolveAddress(_ s: NetService) {
            MainActor.assumeIsolated {
                // "ecb5fa98e9ef.local." → without the trailing dot, so it
                // matches the host URLSession reports.
                if let name = s.hostName { finish(name.hasSuffix(".") ? String(name.dropLast()) : name) }
            }
        }
    }
}

struct HueError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    /// Shown as the lamp status; `AppState.localNetworkDenied` recognises it
    /// to offer the button that opens the setting.
    static let localNetworkDenied = HueError("Sundial isn't allowed to find devices on your network, so it can't reach the Hue Bridge. Click Open Privacy & Security, choose Local Network, and switch Sundial on.")
    var errorDescription: String? { message }
}
