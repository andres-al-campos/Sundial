import SwiftUI

// MARK: - macOS 26 MenuBarExtra(.window) zero-height workaround
//
// Under macOS 26, a `ScrollView` sized with only `.frame(maxHeight:)` collapses to
// ZERO height inside `MenuBarExtra(.window)` when the enclosing layout has no
// concrete height — the panel renders blank (header + Quit visible, the content in
// between gone). The data layer is fine; it's purely a SwiftUI layout regression.
//
// Fix: measure the scroll *content's* natural height with a GeometryReader +
// PreferenceKey, then pin the ScrollView to a CONCRETE `.frame(height:)` clamped
// between a floor (so it never collapses before the first measurement) and a cap
// (so it grows to fit content, then scrolls for overflow). Do NOT revert any of
// these panels to a `maxHeight`-only frame — that reintroduces the blank-menu bug.
//
// Usage:
//   ScrollView {
//       VStack { ... }
//           .measureContentHeight()      // on the CONTENT, inside the ScrollView
//   }
//   .scrollContentHeight("presets", cap: 320, initial: h)   // on the ScrollView
//
// Each open builds a fresh view, and starting from 0 made the popup open at
// the floor and then jump to the content height. So it starts from the last
// height measured under `key`, or on the first open after launch from
// `initial`, the caller's best computation of the content's height.
//
// The two halves talk via the ContentHeightKey preference, so the reader always
// reflects the laid-out content rather than the (clamped) ScrollView frame.

/// Carries the scroll content's measured natural height up to the ScrollView.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Apply to the content *inside* a ScrollView so its natural height is published
    /// to an enclosing `.scrollContentHeight(_:cap:)`.
    func measureContentHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
    }

    /// Apply to a ScrollView whose content uses `.measureContentHeight()`. Frames the
    /// ScrollView to the measured content height clamped to `floor...cap`: it grows to
    /// fit content up to `cap`, then scrolls. Survives MenuBarExtra(.window) on macOS 26.
    ///
    /// - Parameters:
    ///   - key: Names the panel; its last measured height is the next open's start.
    ///   - initial: Starting height when nothing has been measured under `key` yet.
    ///   - cap: Maximum panel height. Content taller than this scrolls.
    ///   - floor: Minimum height, applied before the first measurement so the panel
    ///            never collapses to zero. Defaults to 44.
    func scrollContentHeight(_ key: String, cap: CGFloat, initial: CGFloat, floor: CGFloat = 44) -> some View {
        modifier(ScrollContentHeight(key: key, cap: cap, initial: initial, floor: floor))
    }
}

private struct ScrollContentHeight: ViewModifier {
    /// Last measured height per panel, kept across opens.
    @MainActor private static var lastHeight: [String: CGFloat] = [:]

    let key: String
    let cap: CGFloat
    let floor: CGFloat
    @State private var measured: CGFloat

    init(key: String, cap: CGFloat, initial: CGFloat, floor: CGFloat) {
        self.key = key
        self.cap = cap
        self.floor = floor
        _measured = State(initialValue: Self.lastHeight[key] ?? initial)
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ContentHeightKey.self) { height in
                measured = height
                Self.lastHeight[key] = height
            }
            .frame(height: min(max(measured, floor), cap))
    }
}
