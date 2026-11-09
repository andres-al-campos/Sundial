import SwiftUI

/// Row heights for the list's cap: the viewport shows one expanded card, the
/// line under it and one collapsed neighbour before scrolling, with nothing
/// peeking below.
private enum Row {
    /// Collapsed card: pinned with a frame on the header row.
    static let collapsed: CGFloat = 56
    /// Expanded card: collapsed header + inline editor (time/toggle row, three
    /// sliders, actions row) + its 12pt bottom padding, as measured in the window
    /// on 2026-11-08 (189 was the popup's). Only the first open's start: the rendered
    /// card is measured (`ExpandedHeightKey`) and that wins, so an editor change can't
    /// leave a gap or cut a card, but a wrong start resizes the scroll bar's handle twice.
    static let expanded: CGFloat = 190.5
    /// "No presets yet" block. Estimated.
    static let emptyState: CGFloat = 70
    /// One expanded card, its divider and one collapsed card.
    static func cap(expanded: CGFloat) -> CGFloat { expanded + 1 + collapsed }
}

/// Carries the expanded card's rendered height up to the list's cap.
private struct ExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PresetListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var expandedPresetID: UUID?
    @State private var sortedPresets: [Preset]
    /// The expanded card's height as last rendered, kept across opens so the
    /// popup opens at the size it closed at.
    @MainActor private static var lastExpanded = Row.expanded
    @State private var expandedHeight = PresetListView.lastExpanded
    @State private var settleTask: Task<Void, Never>?
    /// The height the list keeps while a card closes, so the rows glide up inside it before it
    /// shrinks. Shrinking at once clamped the scroll position and snapped the list.
    @State private var held: CGFloat = 0
    /// Where the list is scrolled to. A class, so following the scroll doesn't redraw the list.
    @State private var scrolled = ScrollSpot()
    /// The list's height before its first measurement, worked out from the rows.
    private let initialHeight: CGFloat
    /// The tallest the list may get. In the desktop window, the room it has.
    private let height: CGFloat
    private let width: CGFloat
    private let inset: CGFloat

    /// Takes `appState` here as well as from the environment so the list starts
    /// with its rows and its height: filling them in after the first layout
    /// showed the empty state for a frame and resized the popup.
    init(expandedPresetID: Binding<UUID?>, appState: AppState, height: CGFloat, width: CGFloat = .infinity, inset: CGFloat = 0) {
        self.height = height
        self.width = width
        self.inset = inset
        _expandedPresetID = expandedPresetID
        let sorted = Self.sorted(appState)
        _sortedPresets = State(initialValue: sorted)
        initialHeight = Self.estimatedHeight(sorted, expanded: expandedPresetID.wrappedValue, expandedHeight: Self.lastExpanded)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                if sortedPresets.isEmpty {
                    VStack(spacing: 6) {
                        Text("No presets yet")
                            .font(.subheadline.weight(.medium))
                        Text("Add one to get started.")
                            .font(.caption)
                            .foregroundStyle(Layout.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                }

                ForEach(sortedPresets) { preset in
                    PresetCardRow(
                        preset: preset,
                        isActive: preset.id == appState.activePresetID,
                        isExpanded: expandedPresetID == preset.id,
                        onExpandToggle: {
                            let wasExpanded = expandedPresetID == preset.id
                            // Unanimated here: the rows animate themselves, below.
                            expandedPresetID = wasExpanded ? nil : preset.id
                            // Re-sort when collapsing so time changes take effect.
                            if wasExpanded { refreshSort() }
                            // Collapsing a row that owned a preview ends it.
                            if wasExpanded, appState.previewingPresetID == preset.id {
                                endPreview()
                            }
                            // No scroll to the opened card: a header moves only when the
                            // user scrolls, and scrolling it to the top jumped it once the
                            // list grew past the window.
                        }
                    )
                    .id(preset.id)
                    // A new card fades in where it sorts while the rows below slide down for it.
                    .transition(.opacity)
                    // The last card's line would double the footer's.
                    if preset.id != sortedPresets.last?.id { Divider().transition(.opacity) }
                }
            }
            // Placed from the left edge, not centered: a scroll bar that takes room narrows
            // the scroll view, and centering in it slid the column sideways as the bar came
            // and went. The bar sits in the margin on the right.
            .padding(.horizontal, inset)
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rows animate, and the scroll view gets their final height at once. A
            // withAnimation around the change animated the scroll view's own content size
            // too, whatever the frame said, resizing the scroll bar's handle on every frame.
            .animation(.easeInOut(duration: 0.15), value: expandedPresetID)
            .animation(.easeInOut(duration: 0.15), value: sortedPresets.map(\.id))
            .frame(height: finalHeight.map { max($0, held) }, alignment: .top)
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.frame(in: .named(Self.space)).minY, initial: true) { _, y in scrolled.y = -y }
            })
            .measureContentHeight()
        }
        // A card's first layout reports 195, its settled one 189 ~40ms later
        // (probably its AppKit controls sizing themselves), so the cap takes a height
        // only once it has held for 0.1s; following each would bounce the popup.
        .onPreferenceChange(ExpandedHeightKey.self) { height in
            guard height > Row.collapsed else { return }
            settleTask?.cancel()
            settleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, height != expandedHeight else { return }
                expandedHeight = height
                Self.lastExpanded = height
            }
        }
        // Concrete, self-sizing height — a maxHeight-only frame collapses to 0 inside
        // MenuBarExtra(.window) on macOS 26. Cap = 1 expanded card + 1 collapsed card
        // (heights pinned via Row above), so expanding a card shows itself + exactly one
        // collapsed neighbor, then scrolls. Grows to fit content below the cap.
        .coordinateSpace(name: Self.space)
        .scrollContentHeight("presets", cap: height, initial: initialHeight)
        .onChange(of: finalHeight) { old, new in
            guard let new, let old, new < old else { held = new ?? 0; return }
            // Closing below the new end: scroll there with the rows, so the list arrives as it
            // shrinks instead of jumping.
            if scrolled.y > new - height, let last = sortedPresets.last?.id {
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if finalHeight == new { held = new }
            }
        }
        .onAppear {
            refreshSort()
            // Scroll the currently-active preset to the top of the viewport on open.
            // Deferred so the sort + layout settle before the scroll target is applied.
            if let active = appState.activePresetID {
                DispatchQueue.main.async {
                    proxy.scrollTo(active, anchor: .top)
                }
            }
        }
        .onChange(of: appState.presets.count) { old, new in
            refreshSort()
            // A preset added opens where it sorts. The list scrolls only when that's out of
            // view, and during the rows' own animation: a scroll after it moved everything twice.
            guard new > old, let id = expandedPresetID, let at = sortedPresets.firstIndex(where: { $0.id == id }) else { return }
            let top = CGFloat(at) * (Row.collapsed + 1)
            if top < scrolled.y || top + expandedHeight > scrolled.y + height {
                // Next turn: in this one the new row isn't laid out yet, and a scroll to it does nothing.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: top < scrolled.y ? .top : .bottom) }
                }
            }
        }
        }
    }

    private func endPreview() {
        appState.previewingPresetID = nil
        appState.onPreviewEnded?()
    }

    private func refreshSort() {
        sortedPresets = Self.sorted(appState)
    }

    private static func sorted(_ appState: AppState) -> [Preset] {
        appState.presets.sorted { a, b in
            let aTime = appState.schedule.first(where: { $0.presetID == a.id })?.minutesSinceMidnight
            let bTime = appState.schedule.first(where: { $0.presetID == b.id })?.minutesSinceMidnight
            return (aTime ?? Int.max) < (bTime ?? Int.max)
        }
    }

    /// Rows plus the dividers between them, capped. With two or more presets
    /// and one expanded this is the cap, so `Row.emptyState`, a guess, only
    /// matters for an empty list.
    private static let space = "presetList"

    /// The rows' height once the open card has settled; nil with no rows, whose height is a guess.
    private var finalHeight: CGFloat? {
        guard !sortedPresets.isEmpty else { return nil }
        return sortedPresets.reduce(CGFloat(sortedPresets.count - 1)) { sum, p in
            sum + (p.id == expandedPresetID ? expandedHeight : Row.collapsed)
        }
    }

    private static func estimatedHeight(_ presets: [Preset], expanded: UUID?, expandedHeight: CGFloat) -> CGFloat {
        guard !presets.isEmpty else { return Row.emptyState }
        let rows = presets.reduce(CGFloat(0)) { sum, p in
            sum + (p.id == expanded ? expandedHeight : Row.collapsed)
        }
        return min(rows + CGFloat(presets.count - 1), Row.cap(expanded: expandedHeight))
    }
}

// MARK: - The popup's card

/// The preset the schedule has on, open for tweaking. The rest are in the window.
struct CurrentPresetCard: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let preset = appState.preset(for: appState.activePresetID) {
            // It shades on hover like the window's rows, so a click opens it there.
            PresetCardRow(preset: preset, isActive: true, isExpanded: true, onExpandToggle: {
                // The popup is the key window; nothing else closes it as the window comes up.
                NSApp.keyWindow?.close()
                appState.openPreset(preset.id)
            }, collapses: false, insetShade: true)
                .id(preset.id)
        } else {
            Text("No preset is on right now.")
                .font(.subheadline)
                .foregroundStyle(Layout.dim)
                .padding(14)
        }
    }
}

// MARK: - Preset Card Row

private struct PresetCardRow: View {
    let preset: Preset
    let isActive: Bool
    let isExpanded: Bool
    let onExpandToggle: () -> Void
    var collapses = true
    /// The popup's lone card keeps its shade 8 points clear above and below: shaded to its edges it
    /// touched the row above. The window's rows sit between dividers and shade their whole height.
    var insetShade = false

    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded {
                PresetEditor(preset: preset)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background {
            if insetShade {
                Rectangle()
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.vertical, 8)
            } else {
                isHovered ? Color.primary.opacity(0.06) : Color.clear
            }
        }
        .background {
            if isExpanded {
                GeometryReader { proxy in
                    Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { nameDraft = preset.name }
        // Closing the popup ends a name edit (and commits it), so it doesn't
        // reopen still highlighted.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            nameFocused = false
        }
        .onChange(of: preset.name) { _, newValue in
            if !nameFocused { nameDraft = newValue }
        }
    }

    // MARK: Header row

    private var headerRow: some View {
        // The background is the expand hit target. The inline TextField sits above
        // it and captures its own clicks. When the TextField is focused, tapping
        // the background unfocuses it (commit) instead of toggling expand.
        ZStack {
            // Tap-catcher background — fills the row
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if nameFocused {
                        nameFocused = false   // commit via onChange below
                    } else {
                        onExpandToggle()
                    }
                }

            HStack(spacing: 10) {
                Circle()
                    .fill(isActive ? Color.orange : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .frame(maxWidth: 100, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(nameFocused ? Color.primary.opacity(0.08) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    nameFocused ? Color.accentColor.opacity(0.6) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Layout.dim)
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if nameFocused {
                                nameFocused = false
                            } else {
                                onExpandToggle()
                            }
                        }
                }

                Spacer(minLength: 8)

                if collapses {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .opacity(preset.enabled ? 1.0 : 0.5)
        }
        .frame(height: Row.collapsed)
    }

    private var subtitle: String {
        let time = appState.schedule.first(where: { $0.presetID == preset.id })?.timeString ?? "—"
        return "\(time) · br: \(preset.hardwareBrightness)% · co: \(preset.hardwareContrast)% · ns: \(preset.nightShift)%"
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = preset.name
            return
        }
        guard trimmed != preset.name else { return }
        var updated = preset
        updated.name = trimmed
        appState.updatePreset(updated)
    }
}

// MARK: - Inline editor

private struct PresetEditor: View {
    let preset: Preset

    var body: some View {
        PresetEditorBody(preset: preset)
            // id forces a fresh state instance when a different preset row expands
            .id(preset.id)
    }
}

private struct PresetEditorBody: View {
    let preset: Preset

    @EnvironmentObject var appState: AppState
    @State private var draft: Preset
    @State private var scheduleEntry: ScheduleEntry?
    @State private var scheduleTime: Date = Date()
    @State private var sliderApplyTask: Task<Void, Never>?
    /// True while a drag on the active preset holds `previewingPresetID` — see `beginSliderEdit`.
    @State private var claimedForSliderEdit = false
    /// True while the monitor is in HDR, where it stores the contrast it's sent
    /// but doesn't apply it. The slider greys out so it doesn't look broken.
    @State private var contrastLockedByHDR = false

    init(preset: Preset) {
        self.preset = preset
        _draft = State(initialValue: preset)
        _scheduleEntry = State(initialValue: nil)
    }

    /// True when this preset is the currently-running one (scheduler's active preset).
    /// In that case, editing applies live by definition — there's no "preview" concept.
    private var isActivePreset: Bool {
        appState.activePresetID == draft.id
    }

    /// True when this preset owns the current preview (manually or auto-started).
    private var isPreviewing: Bool {
        appState.previewingPresetID == draft.id
    }

    /// True when slider changes should apply live to the monitor.
    private var liveApply: Bool { isActivePreset || isPreviewing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Time + Enabled (same row to save vertical space)
            HStack {
                Text("Time")
                    .font(.caption)
                    .frame(width: 72, alignment: .leading)
                TimeField(label: "Time", time: $scheduleTime)
                    .onChange(of: scheduleTime) { _, newValue in
                        updateScheduleTime(newValue)
                    }
                Spacer()
                Text("Enabled")
                    .font(.caption)
                Toggle("", isOn: Binding(
                    get: { draft.enabled },
                    set: { newValue in
                        draft.enabled = newValue
                        persist()
                        appState.onScheduleChanged?()
                    }
                ))
                .labelsHidden()
                .controlSize(.mini)
                .toggleStyle(.switch)
            }

            // Sliders
            LabeledSlider(
                label: "Brightness",
                value: $draft.hardwareBrightness,
                onLiveChange: { newValue in
                    guard liveApply else { return }
                    scheduleApply("hardwareBrightness", value: newValue)
                },
                onEditingBegan: { beginSliderEdit() },
                onCommit: {
                    persist()
                    if liveApply { applyNow() }
                    endSliderEdit()
                }
            )
            LabeledSlider(
                label: "Contrast",
                value: $draft.hardwareContrast,
                lockedNote: contrastLockedByHDR ? "Locked by monitor in HDR" : nil,
                onLiveChange: { newValue in
                    guard liveApply else { return }
                    scheduleApply("hardwareContrast", value: newValue)
                },
                onEditingBegan: { beginSliderEdit() },
                onCommit: {
                    persist()
                    if liveApply { applyNow() }
                    endSliderEdit()
                }
            )
            LabeledSlider(
                label: "Night Shift",
                value: $draft.nightShift,
                onLiveChange: { newValue in
                    guard liveApply else { return }
                    NightShiftController.setStrength(newValue)
                },
                onEditingBegan: { beginSliderEdit() },
                onCommit: {
                    persist()
                    endSliderEdit()
                }
            )

            // Actions
            HStack(spacing: 8) {
                if isActivePreset {
                    // No button — this preset IS the monitor. Just a status label.
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .help("This is the active preset — edits apply to the monitor in real time.")
                } else {
                    Button {
                        togglePreview()
                    } label: {
                        Label(isPreviewing ? "Previewing" : "Preview",
                              systemImage: isPreviewing ? "eye.fill" : "eye")
                    }
                    .controlSize(.small)
                    .tint(isPreviewing ? .orange : nil)
                    .buttonStyle(.bordered)
                    .hoverShade()
                }

                Spacer()

                Button(role: .destructive) {
                    if isPreviewing { endPreview() }
                    appState.deletePreset(id: draft.id)
                    appState.onScheduleChanged?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
                .hoverShade()
            }
        }
        .opacity(draft.enabled ? 1.0 : 0.6)
        .onAppear {
            loadSchedule()
            refreshHDR()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in refreshHDR() }
        .onDisappear {
            releaseSliderClaimIfNeeded()
            if isPreviewing { endPreview() }
            sliderApplyTask?.cancel()
        }
    }

    private func refreshHDR() {
        contrastLockedByHDR = HDRState.isOn(displayName: appState.displayName)
    }

    // MARK: - Schedule helpers

    private func loadSchedule() {
        if let entry = appState.schedule.first(where: { $0.presetID == draft.id }) {
            scheduleEntry = entry
            var comps = DateComponents()
            comps.hour = entry.hour
            comps.minute = entry.minute
            scheduleTime = Calendar.current.date(from: comps) ?? Date()
        } else {
            let entry = ScheduleEntry(presetID: draft.id, hour: 12, minute: 0)
            appState.addScheduleEntry(entry)
            scheduleEntry = entry
            var comps = DateComponents()
            comps.hour = 12
            comps.minute = 0
            scheduleTime = Calendar.current.date(from: comps) ?? Date()
        }
    }

    private func updateScheduleTime(_ date: Date) {
        guard var entry = scheduleEntry else { return }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        entry.hour = comps.hour ?? entry.hour
        entry.minute = comps.minute ?? entry.minute
        appState.updateScheduleEntry(entry)
        scheduleEntry = entry
        // Moving a time may change which entry is active right now.
        appState.onScheduleChanged?()
    }

    private func persist() {
        appState.updatePreset(draft)
    }

    // MARK: - Preview / Live apply

    private func togglePreview() {
        if isPreviewing {
            endPreview()
        } else {
            appState.previewingPresetID = draft.id
            applyNow()
        }
    }

    private func endPreview() {
        sliderApplyTask?.cancel()
        appState.previewingPresetID = nil
        // For the active preset, re-apply it (restores monitor after any
        // interrupted preview drift). For others, scheduler snaps back.
        appState.onPreviewEnded?()
    }

    private func applyNow() {
        let snapshot = draft
        let controller = DDCController(displayName: appState.displayName)
        sliderApplyTask?.cancel()
        sliderApplyTask = Task { await controller.apply(snapshot) }
    }

    /// Claim the monitor for the duration of a slider drag.
    ///
    /// Without this the scheduler's minute tick sees the display no longer matching
    /// the scheduled preset — which is exactly what dragging a slider does — and
    /// re-applies the preset, undoing the drag. Night Shift appeared to work only
    /// because `state(of:)` reads brightness and contrast and cannot see it.
    ///
    /// Only claims when nothing else is previewing, so an explicit preview of
    /// another preset keeps ownership and is restored untouched on release.
    /// Drop a drag lock if the row goes away mid-drag (row collapsed, menu
    /// closed), so this row's flag doesn't outlive the drag.
    private func releaseSliderClaimIfNeeded() {
        guard claimedForSliderEdit else { return }
        claimedForSliderEdit = false
        if appState.previewingPresetID == draft.id {
            appState.previewingPresetID = nil
            appState.onPreviewEnded?()
        }
    }

    /// Take the monitor when a slider drag starts.
    ///
    /// Without a lock the scheduler's minute tick sees the display not matching
    /// the scheduled preset and reverts the drag.
    ///
    /// On a non-active preset the drag enters preview, same as pressing the
    /// Preview button, and stays there after release so you can judge the result.
    /// It ends the usual ways: Preview button, collapsing the row, closing the menu.
    ///
    /// The active preset has no preview mode, so it only locks for the drag
    /// itself; its edits persist and the scheduler applies them.
    private func beginSliderEdit() {
        if isActivePreset {
            guard appState.previewingPresetID == nil else { return }
            claimedForSliderEdit = true
            appState.previewingPresetID = draft.id
        } else if !isPreviewing {
            // Apply the whole preset first, so the screen shows this preset
            // and not just the one parameter being dragged.
            appState.previewingPresetID = draft.id
            applyNow()
        }
    }

    /// Release the active preset's drag lock. Non-active previews keep holding.
    private func endSliderEdit() {
        guard claimedForSliderEdit else { return }
        claimedForSliderEdit = false
        appState.previewingPresetID = nil
        appState.onPreviewEnded?()
    }

    /// Debounced single-param apply — cancels any in-flight task so rapid slider
    /// movement only sends the final value, without touching other params.
    private func scheduleApply(_ param: String, value: Int) {
        sliderApplyTask?.cancel()
        let displayName = appState.displayName
        sliderApplyTask = Task {
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }
            let controller = DDCController(displayName: displayName)
            await controller.applySingle(param, value: value)
        }
    }
}

// MARK: - Labeled slider

struct LabeledSlider: View {
    let label: String
    @Binding var value: Int
    /// Why the slider can't be moved right now, or nil when it can. A lock
    /// sits beside the label and the note is shown where the slider would be:
    /// a slider that can't move has nothing to show. It takes the slider's
    /// place so the card keeps its height either way (see `Row`), and it
    /// isn't a `.help` tooltip because those don't appear in this menu. Keep
    /// it short: the slot is ~170pt.
    var lockedNote: String?
    var onLiveChange: ((Int) -> Void)?
    var onEditingBegan: (() -> Void)?
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(label)
                if lockedNote != nil {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .frame(width: 72, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newValue in
                        let rounded = Int(newValue.rounded())
                        if rounded != value {
                            value = rounded
                            onLiveChange?(rounded)
                        }
                    }
                ),
                in: 0...100,
                onEditingChanged: { editing in
                    if editing { onEditingBegan?() } else { onCommit() }
                }
            )
            .controlSize(.small)
            .disabled(lockedNote != nil)
            // Hidden, not removed, so the row keeps the slider's height.
            .opacity(lockedNote == nil ? 1 : 0)
            .overlay(alignment: .leading) {
                if let lockedNote {
                    Text(lockedNote)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Text("\(value)%")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
        .foregroundStyle(lockedNote == nil ? Color.primary : Layout.dim)
    }
}

/// A scroll position kept without redrawing whoever keeps it.
private final class ScrollSpot { var y: CGFloat = 0 }
