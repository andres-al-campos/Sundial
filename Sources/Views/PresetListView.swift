import SwiftUI

/// Fixed row heights so the panel cap is exact rather than measured/estimated.
/// The viewport shows `expanded + collapsed` (one expanded card + one collapsed
/// neighbor) before scrolling — see `cap` on the ScrollView below.
private enum Row {
    /// Collapsed card: name + subtitle + 10pt vertical padding top & bottom.
    static let collapsed: CGFloat = 56
    /// Expanded card: collapsed header + inline editor (time/toggle row, three
    /// sliders, actions row) + its 12pt bottom padding. Measured from the rendered
    /// card via a GeometryReader (settles at ~195pt).
    static let expanded: CGFloat = 195
}

struct PresetListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var expandedPresetID: UUID?
    @State private var sortedPresets: [Preset] = []

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
                            .foregroundStyle(.secondary)
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expandedPresetID = wasExpanded ? nil : preset.id
                            }
                            // Re-sort when collapsing so time changes take effect.
                            if wasExpanded { refreshSort() }
                            // Collapsing a row that owned a preview ends it.
                            if wasExpanded, appState.previewingPresetID == preset.id {
                                endPreview()
                            }
                            // Scroll expanded row to the top of the viewport after the
                            // expand animation settles.
                            if !wasExpanded {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation { proxy.scrollTo(preset.id, anchor: .top) }
                                }
                            }
                        }
                    )
                    .id(preset.id)
                    Divider()
                }

                Button {
                    let newPreset = Preset(
                        name: "New Preset",
                        hardwareBrightness: 70,
                        hardwareContrast: 75,
                        nightShift: 0
                    )
                    appState.addPreset(newPreset)
                    appState.addScheduleEntry(
                        ScheduleEntry(presetID: newPreset.id, hour: 12, minute: 0)
                    )
                    appState.onScheduleChanged?()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedPresetID = newPreset.id
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { proxy.scrollTo(newPreset.id, anchor: .top) }
                    }
                } label: {
                    Label("Add Preset", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .measureContentHeight()
        }
        // Concrete, self-sizing height — a maxHeight-only frame collapses to 0 inside
        // MenuBarExtra(.window) on macOS 26. Cap = 1 expanded card + 1 collapsed card
        // (heights pinned via Row above), so expanding a card shows itself + exactly one
        // collapsed neighbor, then scrolls. Grows to fit content below the cap.
        .scrollContentHeight(cap: Row.expanded + Row.collapsed)
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
        .onChange(of: appState.presets.count) { refreshSort() }
        }
    }

    private func endPreview() {
        appState.previewingPresetID = nil
        appState.onPreviewEnded?()
    }

    private func refreshSort() {
        sortedPresets = appState.presets.sorted { a, b in
            let aTime = appState.schedule.first(where: { $0.presetID == a.id })?.minutesSinceMidnight
            let bTime = appState.schedule.first(where: { $0.presetID == b.id })?.minutesSinceMidnight
            return (aTime ?? Int.max) < (bTime ?? Int.max)
        }
    }
}

// MARK: - Preset Card Row

private struct PresetCardRow: View {
    let preset: Preset
    let isActive: Bool
    let isExpanded: Bool
    let onExpandToggle: () -> Void

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
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { isHovered = $0 }
        .onAppear { nameDraft = preset.name }
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
                        .foregroundStyle(.secondary)
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

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .allowsHitTesting(false)
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
    /// True while a slider drag holds `previewingPresetID` — see `beginSliderEdit`.
    @State private var claimedForSliderEdit = false

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
                DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .controlSize(.small)
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
            }
        }
        .opacity(draft.enabled ? 1.0 : 0.6)
        .onAppear {
            loadSchedule()
        }
        .onDisappear {
            releaseSliderClaimIfNeeded()
            if isPreviewing { endPreview() }
            sliderApplyTask?.cancel()
        }
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
        let controller = DDCController(cliPath: appState.cliPath, displayName: appState.displayName)
        sliderApplyTask?.cancel()
        sliderApplyTask = Task { await controller.apply(snapshot) }
    }

    /// Claim the monitor for the duration of a slider drag.
    ///
    /// Without this the scheduler's 15s tick sees the display no longer matching
    /// the scheduled preset — which is exactly what dragging a slider does — and
    /// re-applies the preset, undoing the drag. Night Shift appeared to work only
    /// because `state(of:)` reads brightness and contrast and cannot see it.
    ///
    /// Only claims when nothing else is previewing, so an explicit preview of
    /// another preset keeps ownership and is restored untouched on release.
    /// Drop a stale claim if the row goes away mid-drag (row collapsed, menu
    /// closed). Both of those paths already clear `previewingPresetID` globally;
    /// this just keeps this row's flag from lying on the way back in.
    private func releaseSliderClaimIfNeeded() {
        guard claimedForSliderEdit else { return }
        claimedForSliderEdit = false
        if appState.previewingPresetID == draft.id {
            appState.previewingPresetID = nil
            appState.onPreviewEnded?()
        }
    }

    private func beginSliderEdit() {
        guard appState.previewingPresetID == nil else { return }
        claimedForSliderEdit = true
        appState.previewingPresetID = draft.id
    }

    /// Release the claim taken by `beginSliderEdit`, and let the scheduler decide
    /// what should be on screen now. Only releases a claim this drag took.
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
        let cliPath = appState.cliPath
        let displayName = appState.displayName
        sliderApplyTask = Task {
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }
            let controller = DDCController(cliPath: cliPath, displayName: displayName)
            await controller.applySingle(param, value: value)
        }
    }
}

// MARK: - Labeled slider

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Int
    var onLiveChange: ((Int) -> Void)?
    var onEditingBegan: (() -> Void)?
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
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
            Text("\(value)%")
                .font(.caption.monospacedDigit())
                .frame(width: 32, alignment: .trailing)
        }
    }
}
