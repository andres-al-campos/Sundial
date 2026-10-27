import AppKit

/// Whether a display is currently in HDR mode.
///
/// Read from macOS rather than BetterDisplay: the CLI's `-hdr` query is a Pro
/// feature, and everything else Sundial uses is free.
enum HDRState {
    /// A screen reduced to what the decision reads, so it can be checked
    /// without a display attached.
    struct Screen {
        var name: String
        /// `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue`:
        /// above 1 when the display can show brighter-than-white right now.
        var potentialHeadroom: Double
    }

    /// True when a screen matching `displayName` has HDR headroom. The match is
    /// a case-insensitive partial one, the same as BetterDisplay's `-nameLike`,
    /// so one setting names the display for both.
    static func isOn(displayName: String, screens: [Screen]) -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return screens.contains {
            $0.name.localizedCaseInsensitiveContains(name) && $0.potentialHeadroom > 1
        }
    }

    @MainActor
    static func isOn(displayName: String) -> Bool {
        isOn(displayName: displayName, screens: NSScreen.screens.map {
            Screen(name: $0.localizedName,
                   potentialHeadroom: $0.maximumPotentialExtendedDynamicRangeColorComponentValue)
        })
    }
}
