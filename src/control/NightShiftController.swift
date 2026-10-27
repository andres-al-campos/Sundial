import Foundation
import ObjectiveC.runtime

/// Wraps macOS's private `CoreBrightness` framework to drive Night Shift
/// (the same thing System Settings → Displays → Night Shift controls).
///
/// This is a private API — Apple could change or remove it. It has been
/// stable since 10.12.4 though, and many menu bar apps use it. Not viable
/// for the Mac App Store, fine for direct distribution.
enum NightShiftController {
    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil else {
            print("[Sundial] Could not load CoreBrightness. Night Shift control will be a no-op. This framework is private and may have moved in your macOS version — check /System/Library/PrivateFrameworks/CoreBrightness.framework exists.")
            return nil
        }
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            print("[Sundial] CBBlueLightClient class missing from CoreBrightness. Night Shift control disabled. Try updating macOS or report to Sundial as a compatibility issue.")
            return nil
        }
        return cls.init()
    }()

    /// Set Night Shift strength (0–100).
    /// 0 disables Night Shift; >0 enables with the given strength.
    static func setStrength(_ percent: Int) {
        guard let client else { return }
        let clamped = max(0, min(100, percent))
        let strength = Float(clamped) / 100.0

        // setStrength:commit:
        let setStrengthSel = NSSelectorFromString("setStrength:commit:")
        if client.responds(to: setStrengthSel) {
            typealias Fn = @convention(c) (AnyObject, Selector, Float, Bool) -> Bool
            let imp = client.method(for: setStrengthSel)
            let fn = unsafeBitCast(imp, to: Fn.self)
            _ = fn(client, setStrengthSel, strength, true)
        }

        // setEnabled:
        let setEnabledSel = NSSelectorFromString("setEnabled:")
        if client.responds(to: setEnabledSel) {
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
            let imp = client.method(for: setEnabledSel)
            let fn = unsafeBitCast(imp, to: Fn.self)
            _ = fn(client, setEnabledSel, clamped > 0)
        }
    }
}
