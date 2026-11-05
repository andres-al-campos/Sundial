import AppKit
import ObjectiveC

/// Makes this process believe it's the frontmost app without being it, with every window off-screen,
/// so a drive never takes the keyboard or the screen from whoever is using the Mac: "yes i still
/// use the computer when you use it". AppKit controls take the clicks this way. SwiftUI's own
/// gestures don't, so a drive reaches those through their state instead.
@MainActor func stayOutOfTheWay() {
    func answerTrue(_ c: AnyClass, _ names: [String]) {
        for name in names {
            guard let m = class_getInstanceMethod(c, NSSelectorFromString(name)) else { continue }
            let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
            method_setImplementation(m, imp_implementationWithBlock(yes))
        }
    }
    answerTrue(NSApplication.self, ["isActive", "_isActiveApp"])
    answerTrue(NSWindow.self, ["isKeyWindow", "hasKeyAppearance", "_hasKeyAppearance", "isMainWindow", "hasMainAppearance",
                               "_hasMainAppearance", "_hasActiveAppearance", "_hasActiveAppearanceIgnoringKeyFocus",
                               "_hasActiveControls", "_wasActiveBeforeCurrentEvent"])
    let staysBehind: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
    method_setImplementation(class_getInstanceMethod(NSApplication.self, #selector(NSApplication.activate(ignoringOtherApps:)))!, imp_implementationWithBlock(staysBehind))
    let staysBehindToo: @convention(block) (AnyObject) -> Void = { _ in }
    if let m = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.activate as (NSApplication) -> () -> Void)) {
        method_setImplementation(m, imp_implementationWithBlock(staysBehindToo))
    }
    let noDockIcon: @convention(block) (AnyObject, Int) -> Bool = { _, _ in true }
    method_setImplementation(class_getInstanceMethod(NSApplication.self, #selector(NSApplication.setActivationPolicy(_:)))!, imp_implementationWithBlock(noDockIcon))
    let anywhere: @convention(block) (AnyObject, NSRect, NSScreen?) -> NSRect = { _, r, _ in r }
    method_setImplementation(class_getInstanceMethod(NSWindow.self, #selector(NSWindow.constrainFrameRect(_:to:)))!, imp_implementationWithBlock(anywhere))
    let offScreen: @convention(block) (NSWindow, AnyObject?) -> Void = { w, _ in
        w.setFrameOrigin(NSPoint(x: -8000, y: 200))
        w.orderFront(nil)
    }
    method_setImplementation(class_getInstanceMethod(NSWindow.self, #selector(NSWindow.makeKeyAndOrderFront(_:)))!, imp_implementationWithBlock(offScreen))
}

/// Saves one window to a PNG. A window of this process needs no Screen Recording permission.
@MainActor func capture(_ w: NSWindow, to path: String) -> Bool {
    guard let n = CGWindowID(exactly: w.windowNumber),
          let i = CGWindowListCreateImage(.null, .optionIncludingWindow, n, [.boundsIgnoreFraming, .bestResolution]),
          let d = NSBitmapImageRep(cgImage: i).representation(using: .png, properties: [:]) else { return false }
    return (try? d.write(to: URL(fileURLWithPath: path))) != nil
}
