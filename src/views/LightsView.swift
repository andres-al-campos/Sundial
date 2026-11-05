import SwiftUI

/// Every edit to the bulbs goes through here, so undo needs no per-action code:
/// the whole setup is one value, and after anything you do, if it changed, the
/// version before it is kept. A drag or slider move commits once, on release.
@MainActor
final class LightsHistory: ObservableObject {
    private weak var state: AppState?
    private var committed: [LightDay.Bulb]?

    func attach(_ state: AppState) {
        guard self.state == nil else { return }
        self.state = state
        committed = state.lights
    }

    /// The bridge read the bulbs, not you: nothing to undo.
    func seen(_ lights: [LightDay.Bulb]?) { committed = lights }

    func commit(_ undo: UndoManager?, _ name: String) {
        guard let state, state.lights != committed else { return }
        let before = committed
        committed = state.lights
        register(before, undo, name)
        finish(from: before)
    }

    private func register(_ version: [LightDay.Bulb]?, _ undo: UndoManager?, _ name: String) {
        undo?.setActionName(name)
        undo?.registerUndo(withTarget: self) { history in
            MainActor.assumeIsolated {
                guard let state = history.state else { return }
                let current = history.committed
                state.lights = version
                history.committed = version
                history.register(current, undo, name)
                history.finish(from: current)
            }
        }
    }

    private func finish(from before: [LightDay.Bulb]?) {
        guard let state else { return }
        state.save()
        for bulb in state.lights ?? [] {
            if let old = before?.first(where: { $0.id == bulb.id }), old.name != bulb.name {
                state.onRenameBulb?(bulb.deviceID, bulb.name)
            }
        }
        state.onLampsChanged?()
    }
}

/// One row per bulb across the day, the band being what the bulb does: its colour,
/// dimmed by its brightness. Click a band for a keyframe, drag one to move it,
/// click one for its settings on the card that comes down below, or click a bulb's
/// name to change it right now. Right-click for copy, paste and linking.
struct LightsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undo
    @StateObject private var history = LightsHistory()

    @State private var selection: Selection?
    @State private var dragging: UUID?
    @State private var dragLook: LightDay.State?
    @State private var clip: Clip = .init()
    @State private var renaming: String?
    @State private var playMinute: Double?
    @State private var playTask: Task<Void, Never>?
    @State private var previewing: Previewing?
    /// What the card last showed, so it still has it while it slides away. Something from
    /// the start, because a card whose contents are new on its first open jumps open
    /// instead of sliding.
    @State private var lastShown = Shown(bulb: "", bulbID: "", key: nil, look: .init(on: true, brightness: 0, xy: .init(x: 0.4, y: 0.4)))
    /// What the lamps were doing when one was last selected, for its right-now card.
    @State private var lampsNow: [String: LightDay.State] = [:]

    /// Follows the selection a step behind, so the card already shows the keyframe when it
    /// starts to move. In one step the slide also caught its text and sliders, which
    /// travelled from the last keyframe's places, overlapping on the way.
    @State private var cardOpen = false

    /// With no keyframe, it's the bulb itself, right now.
    struct Selection: Equatable { var bulb: String; var key: UUID? }
    struct Clip { var key: LightDay.Key?; var day: [LightDay.Key]? }
    struct Previewing { var bulb: String; var look: LightDay.State; var minute: Int }
    struct Shown: Equatable { var bulb: String; var bulbID: String; var key: LightDay.Key?; var look: LightDay.State }

    private var bulbs: [LightDay.Bulb] { appState.lights ?? [] }

    /// Read fresh, with the body rebuilt on the minute by its `TimelineView`. A timer
    /// made as a property here is remade whenever the parent redraws, and each new
    /// one starts its wait over.
    private var now: Date { Date() }

    private var marks: LightDay.Marks {
        LightDay.Marks(warm: SunClock.schedule(on: now, bedtime: appState.bedtime), sun: SunClock.sun(on: now))
    }

    private var nowMinute: Double {
        let c = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private var lineMinute: Double { playMinute ?? nowMinute }

    var body: some View {
        TimelineView(.everyMinute) { _ in
            VStack(spacing: 0) {
                toolbar
                Divider()
                if appState.hueHost == nil {
                    unpaired
                } else if bulbs.isEmpty {
                    ProgressView("Reading your bulbs…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    lightsAndCard
                }
            }
        }
        .onAppear {
            history.attach(appState)
            appState.onLampsChanged?()
        }
        .onChange(of: appState.lights) { _, new in
            // The bridge's own reads arrive while nothing's being edited.
            if selection == nil, dragging == nil { history.seen(new) }
        }
        .onChange(of: shown) { _, new in if let new { lastShown = new } }
        .onChange(of: selection != nil) { _, selected in cardOpen = selected }
        .onDisappear {
            playTask?.cancel()
            endPreviewNow()
        }
    }

    private var lightsAndCard: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Whether they scroll is settled by the room they'd have with the card out, and
                // that's the scroll view's height either way. A scroll view resized by the
                // slide shows a scroll bar from each frame's rounding. A ViewThatFits here
                // settles it without that, but the card then jumps open instead of sliding.
                if Layout.rowsFit(bulbs.count, in: geo.size.height - Layout.cardRoom) {
                    rows
                } else {
                    ScrollView { rows }
                        .frame(height: geo.size.height - Layout.cardRoom)
                }
                // Anchored at its bottom in a frame that grows, so it comes down from behind
                // the rows and they never move.
                card
                    .frame(height: cardOpen ? Layout.cardRoom : 0, alignment: .bottom)
                    .clipped()
                    .allowsHitTesting(cardOpen)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
            }
            .animation(.easeOut(duration: Layout.slide), value: cardOpen)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Layout.rowGap) {
            marksHeader
            ForEach(bulbs) { row($0) }
            hoursAxis
        }
        .padding(Layout.cardPadding)
        .cardGround()
        .padding(.horizontal, Layout.edge)
        .padding(.top, Layout.rowsPadding)
        .contentShape(Rectangle())
        .onTapGesture { deselect() }
    }

    // MARK: - The card

    private var shown: Shown? {
        guard let selection else { return nil }
        let name = bulbs.first { $0.id == selection.bulb }?.name ?? "Bulb"
        if selection.key == nil {
            return Shown(bulb: name, bulbID: selection.bulb, key: nil, look: rightNow(selection.bulb))
        }
        guard let key = selectedKey else { return nil }
        return Shown(bulb: name, bulbID: selection.bulb, key: key, look: Self.state(key))
    }

    /// Said beside the name, since the two cards look alike and a light isn't one of its keyframes.
    private func kind(of show: Shown) -> String {
        if show.key != nil { return "Keyframe" }
        guard let bulb = bulbs.first(where: { $0.id == show.bulbID }) else { return "" }
        if let parent = bulb.parent { return "Follows \(bulbs.first { $0.id == parent }?.name ?? "another bulb")" }
        return bulb.keys.count == 1 ? "1 Keyframe" : "\(bulb.keys.count) Keyframes"
    }

    /// What a bulb's card starts from: its hold, or the lamp as last read, or where the
    /// day has it until that read comes back.
    private func rightNow(_ id: String) -> LightDay.State {
        if let owner = holdOwner(id), let held = appState.holds[owner]?.look { return held }
        if let read = lampsNow[id] { return read }
        let bulb = bulbs.first { $0.id == id }
        return bulb.flatMap { LightDay.state(LightDay.keys(of: $0, in: bulbs), at: nowMinute, marks: marks) }
            ?? .init(on: true, brightness: 50, xy: LampBlend.xy(mirek: 370))
    }

    private var card: some View {
        let show = shown ?? lastShown
        return LookPanel(
            bulb: show.bulb,
            kind: kind(of: show),
            look: show.look,
            keptFor: show.key?.id.uuidString ?? show.bulbID,
            change: { apply in
                if let key = show.key {
                    change(key.id) { k in
                        var s = Self.state(k)
                        apply(&s)
                        k.on = s.on
                        k.brightness = s.brightness
                        k.xy = s.xy
                    }
                } else {
                    hold(show.bulbID, apply)
                }
            },
            commit: {
                if show.key != nil { history.commit(undo, "Change Keyframe") }
                endPreviewNow()
            }
        ) {
            if let key = show.key {
                KeyTimeRow(key: key, marks: marks, change: { change(key.id, $0) }, commit: {
                    history.commit(undo, "Change Keyframe")
                    endPreviewNow()
                })
            } else {
                HoldRow(held: holdOwner(show.bulbID) != nil, paused: !appState.lampsFollow, back: { backToSchedule(show.bulbID) })
            }
        }
        .padding(Layout.cardPadding)
        .frame(height: Layout.cardHeight)
        .frame(maxWidth: .infinity)
        .cardGround()
        .overlay(alignment: .topTrailing) {
            Button(action: deselect) {
                Image(systemName: "xmark")
                    .frame(width: Layout.iconButton, height: Layout.iconButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .hoverShade()
            .help("Close")
            .padding(Layout.cardPadding - 4)
        }
        .padding(.horizontal, Layout.edge)
        .padding(.bottom, Layout.rowsPadding)
    }

    // MARK: - Bars

    private var toolbar: some View {
        HStack(spacing: 10) {
            // A set height, so the row doesn't move as these swap.
            Group {
                if let previewing {
                    previewBadge(previewing)
                } else if let clockLine {
                    Text(clockLine)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text(statusLine)
                    } icon: {
                        if isPaused { Image(systemName: "pause.fill") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(isPaused ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
            }
            .frame(height: 28)
            .transition(.opacity)
            Spacer()
            Button(playMinute == nil ? "Play the day" : "Stop", action: togglePlay)
                .disabled(bulbs.isEmpty)
                .hoverShade()
            // Filled while paused, because the lamps have stopped following the day and
            // nothing else would say so once you look away from the status line.
            Group {
                if isPaused {
                    Button("Resume", action: togglePause)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                } else {
                    Button(appState.lampsFollow ? "Pause" : "Resume", action: togglePause)
                }
            }
            .disabled(appState.hueHost == nil)
            .hoverShade()
        }
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: previewing == nil)
    }

    private func previewBadge(_ p: Previewing) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.color(p.look))
                .frame(width: 12, height: 12)
            Text("\(p.bulb): \(p.look.on ? "\(Int(p.look.brightness.rounded()))%" : "Off") at \(Self.time(p.minute))")
                .monospacedDigit()
        }
        .font(.title3)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    /// The time the line on the bands is at, when that's what the row is saying.
    private var clockLine: String? {
        if let playMinute { return "Playing, \(Self.time(Int(playMinute)))" }
        if !appState.lampStatus.hasPrefix("Paired"), appState.hueHost != nil { return nil }
        return appState.lampsFollow ? "Now, \(Self.time(Int(nowMinute)))" : nil
    }

    private var isPaused: Bool {
        !appState.lampsFollow && appState.hueHost != nil && appState.lampStatus.hasPrefix("Paired")
    }

    private func togglePause() {
        appState.lampsFollow.toggle()
        appState.save()
        appState.onLampsChanged?()
    }

    private var statusLine: String {
        if !appState.lampStatus.hasPrefix("Paired"), appState.hueHost != nil { return appState.lampStatus }
        return "Paused. The bulbs stay as they are until you resume."
    }

    private var unpaired: some View {
        VStack(spacing: 10) {
            Text("Pair with your Hue Bridge to see your bulbs here.")
                .foregroundStyle(.secondary)
            Button("Pair Hue Bridge") { appState.onPairLamps?() }
                .hoverShade()
            Text(appState.lampStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var marksHeader: some View {
        HStack(spacing: Layout.gap) {
            Color.clear.frame(width: Layout.name, height: 16)
            VStack(spacing: 2) {
                MarkLabels(spots: LightDay.Mark.allCases.map { Layout.position(marks.minute(of: $0)) }) {
                    ForEach(LightDay.Mark.allCases, id: \.self) { mark in
                        Text("\(Self.markName(mark)) \(Self.time(marks.minute(of: mark)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                // Where each mark really is, since a label may have been pushed off it.
                GeometryReader { geo in
                    ForEach(LightDay.Mark.allCases, id: \.self) { mark in
                        Rectangle()
                            .fill(.secondary)
                            .frame(width: 1, height: 4)
                            .offset(x: geo.size.width * Layout.position(marks.minute(of: mark)))
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private var hoursAxis: some View {
        HStack(spacing: Layout.gap) {
            Color.clear.frame(width: Layout.name, height: 14)
            GeometryReader { geo in
                ForEach([6, 9, 12, 15, 18, 21, 0, 3], id: \.self) { hour in
                    Text(Self.hour(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: geo.size.width * Layout.position(hour * 60), y: 7)
                }
            }
            .frame(height: 14)
        }
    }

    // MARK: - A row

    private func row(_ bulb: LightDay.Bulb) -> some View {
        let keys = LightDay.keys(of: bulb, in: bulbs)
        let linked = bulb.parent != nil
        let selected = selection == Selection(bulb: bulb.id, key: nil)
        return HStack(spacing: Layout.gap) {
            name(bulb)
                .frame(width: Layout.name, height: Layout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { rowMenu(bulb) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Band(keys: keys, marks: marks, without: dragLook?.on == true ? dragging : nil)
                        .frame(height: linked ? Layout.linkedHeight : Layout.bandHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(linked ? nil : SpatialTapGesture().onEnded { addKey(bulb, at: $0.location.x, width: geo.size.width) })
                        .contextMenu { bandMenu(bulb, width: geo.size.width) }
                        .onContinuousHover { phase in
                            if case .active(let p) = phase { hoverX = p.x }
                        }
                    // A piece in each row rather than one line over them all, so it stays
                    // under the keyframes. Tall enough to meet the next row's piece, and an
                    // overlay so that doesn't change the row's height.
                    Color.clear
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(.primary.opacity(0.85))
                                .frame(width: 1.5, height: Layout.rowHeight + Layout.rowGap)
                                .offset(x: geo.size.width * Layout.position(lineMinute) - 0.75)
                        }
                        .overlay(alignment: .leading) {
                            if bulb.id == bulbs.last?.id {
                                Circle()
                                    .fill(.primary)
                                    .frame(width: 9, height: 9)
                                    .offset(x: geo.size.width * Layout.position(lineMinute) - 4.5, y: (Layout.rowHeight + Layout.rowGap) / 2)
                            }
                        }
                        .allowsHitTesting(false)
                    if !linked {
                        ForEach(keys) { key in
                            dot(key, bulb: bulb, width: geo.size.width)
                        }
                    }
                }
            }
            .frame(height: Layout.rowHeight)
        }
        // The whole row for the light, while a keyframe of it shows only on its dot. Past the
        // band's end by as much as it shows above and below the band.
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(.primary.opacity(selected ? 0.08 : 0))
                .padding(.trailing, -Layout.bandMargin)
                .animation(.easeOut(duration: 0.15), value: selected)
        }
    }

    /// Where the pointer last was over a band, for the band's right-click menu.
    @State private var hoverX: CGFloat = 0

    @ViewBuilder
    private func name(_ bulb: LightDay.Bulb) -> some View {
        if renaming == bulb.id {
            RenameField(name: bulb.name) { text in
                renaming = nil
                let clean = String(text.trimmingCharacters(in: .whitespaces).prefix(32))
                guard !clean.isEmpty, clean != bulb.name else { return }
                edit { $0[bulb.id]?.name = clean }
                history.commit(undo, "Rename Bulb")
            }
        } else {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bulb.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(holdOwner(bulb.id) != nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    if bulb.parent == nil, LightDay.isUntouchedDefault(bulb.keys) {
                        Text("Click a dot to edit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if bulb.parent != nil {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Follows \(bulbs.first { $0.id == bulb.parent }?.name ?? "another bulb")")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { selectBulb(bulb.id) }
        }
    }

    private func dot(_ key: LightDay.Key, bulb: LightDay.Bulb, width: CGFloat) -> some View {
        let at = LightDay.minute(of: key, marks: marks)
        let look = dragging == key.id ? (dragLook ?? Self.state(key)) : Self.state(key)
        let selected = selection?.key == key.id
        return KeyDot(look: look, selected: selected)
            .contentShape(Circle())
            .position(x: width * Layout.position(at), y: Layout.rowHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { moveKey(key.id, bulb: bulb, to: $0.location.x, width: width) }
                    .onEnded { _ in dropKey(key.id, bulb: bulb) }
            )
            .onTapGesture { toggle(Selection(bulb: bulb.id, key: key.id)) }
            .contextMenu { keyMenu(key, bulb: bulb) }
            .help(Self.keyHelp(key, marks: marks))
    }

    // MARK: - Menus

    @ViewBuilder
    private func keyMenu(_ key: LightDay.Key, bulb: LightDay.Bulb) -> some View {
        Button("Copy Keyframe") { clip.key = key }
        Button("Paste Color and Brightness") { pasteLook(onto: key.id, bulb: bulb) }
            .disabled(clip.key == nil)
        Divider()
        Button("Delete Keyframe") {
            selection = Selection(bulb: bulb.id, key: key.id)
            deleteSelected()
        }
    }

    @ViewBuilder
    private func bandMenu(_ bulb: LightDay.Bulb, width: CGFloat) -> some View {
        Button("Paste Keyframe at \(Self.time(minute(atX: hoverX, width: width)))") {
            guard var key = clip.key else { return }
            key.id = UUID()
            key.minute = minute(atX: hoverX, width: width)
            key.anchor = LightDay.snap(key.minute, marks: marks)
            edit { $0[bulb.id]?.keys.append(key) }
            history.commit(undo, "Paste Keyframe")
        }
        .disabled(clip.key == nil || bulb.parent != nil)
        Divider()
        rowMenu(bulb)
    }

    @ViewBuilder
    private func rowMenu(_ bulb: LightDay.Bulb) -> some View {
        Button("Rename") { renaming = bulb.id }
        Divider()
        Button("Copy This Bulb's Day") { clip.day = LightDay.keys(of: bulb, in: bulbs) }
        Button("Paste Day") {
            guard let day = clip.day else { return }
            edit { $0[bulb.id]?.keys = day.map { var k = $0; k.id = UUID(); return k } }
            history.commit(undo, "Paste Day")
        }
        .disabled(clip.day == nil || bulb.parent != nil)
        Divider()
        if bulb.parent != nil {
            Button("Unlink") { unlink(bulb) }
        } else if !bulbs.contains(where: { $0.parent == bulb.id }) {
            Menu("Follow Another Bulb") {
                ForEach(bulbs.filter { $0.id != bulb.id && $0.parent == nil }) { other in
                    Button(other.name) {
                        edit { $0[bulb.id]?.parent = other.id }
                        if selection?.bulb == bulb.id { selection = nil }
                        history.commit(undo, "Link Bulbs")
                    }
                }
            }
        }
    }

    // MARK: - Editing

    private var selectedKey: LightDay.Key? {
        guard let selection, let id = selection.key else { return nil }
        return bulbs.first { $0.id == selection.bulb }?.keys.first { $0.id == id }
    }

    private func edit(_ change: (inout BulbIndex) -> Void) {
        var index = BulbIndex(bulbs: bulbs)
        change(&index)
        appState.lights = index.bulbs
    }

    private func toggle(_ s: Selection) {
        if selection == s { deselect() } else {
            history.commit(undo, "Change Keyframe")
            // Opening takes the card's slide. A dot with an animation of its own would
            // leave its row behind during that slide.
            if selection == nil { selection = s } else { withAnimation(.easeOut(duration: 0.15)) { selection = s } }
        }
    }

    /// The card for the bulb itself, from what the lamp is doing now.
    private func selectBulb(_ id: String) {
        toggle(Selection(bulb: id, key: nil))
        guard selection?.key == nil, selection?.bulb == id else { return }
        Task { if let read = try? await appState.onReadLamps?() { lampsNow = read } }
    }

    private func holdOwner(_ id: String) -> String? {
        LightDay.holdOwner(of: id, in: bulbs, holds: appState.holds)
    }

    /// Changes the bulb and no keyframes. The first change is what starts the hold. Whichever
    /// follow it show it too, unless they're held themselves.
    private func hold(_ id: String, _ apply: (inout LightDay.State) -> Void) {
        var look = rightNow(id)
        apply(&look)
        appState.holds[id] = LightDay.Hold(look: look, until: LightDay.holdEnd(from: now, sunrise: marks.sunrise))
        var states = [id: look]
        for follower in bulbs where follower.parent == id && appState.holds[follower.id] == nil { states[follower.id] = look }
        appState.onPreviewLamps?(states)
    }

    /// From a follower too, whose button would otherwise do nothing while the hold it's under is another bulb's.
    private func backToSchedule(_ id: String) {
        if let owner = holdOwner(id) { appState.holds[owner] = nil }
        lampsNow = [:]
        // Through the preview's return, for its quick fade rather than the usual 30 seconds.
        endPreviewNow()
    }

    private func deselect() {
        guard selection != nil else { return }
        history.commit(undo, "Change Keyframe")
        selection = nil
        endPreviewNow()
    }

    private func change(_ id: UUID, _ apply: (inout LightDay.Key) -> Void) {
        guard let selection else { return }
        edit { index in
            index.withKey(selection.bulb, id, apply)
        }
        if let key = selectedKey { previewOn(selection.bulb, Self.state(key), at: LightDay.minute(of: key, marks: marks)) }
    }

    /// The bulb, and whichever follow it, show this now.
    private func previewOn(_ bulb: String, _ look: LightDay.State, at minute: Int) {
        var states = [bulb: look]
        for follower in bulbs where follower.parent == bulb { states[follower.id] = look }
        previewing = Previewing(bulb: bulbs.first { $0.id == bulb }?.name ?? "Bulb", look: look, minute: minute)
        appState.onPreviewLamps?(states)
    }

    private func endPreviewNow() {
        previewing = nil
        appState.onEndLampPreview?()
    }

    private func addKey(_ bulb: LightDay.Bulb, at x: CGFloat, width: CGFloat) {
        let at = minute(atX: x, width: width)
        // Adding doesn't change the band: the new keyframe takes what's under it.
        let look = LightDay.state(bulb.keys, at: Double(at), marks: marks)
        let warm = LampBlend.xy(mirek: 370)
        let key = LightDay.Key(minute: at, anchor: LightDay.snap(at, marks: marks), on: look?.on ?? true,
                               brightness: look?.brightness ?? 50, x: look?.xy.x ?? warm.x, y: look?.xy.y ?? warm.y)
        edit { $0[bulb.id]?.keys.append(key) }
        history.commit(undo, "Add Keyframe")
        selection = Selection(bulb: bulb.id, key: key.id)
    }

    /// While dragged a lit keyframe shows what's under it, and on drop it takes that.
    private func moveKey(_ id: UUID, bulb: LightDay.Bulb, to x: CGFloat, width: CGFloat) {
        let at = minute(atX: x, width: width)
        let snapped = LightDay.snap(at, marks: marks)
        let minute = snapped.map { marks.minute(of: $0.mark) } ?? at
        dragging = id
        edit { index in
            index.withKey(bulb.id, id) {
                $0.minute = minute
                $0.anchor = snapped
            }
        }
        if let key = bulb.keys.first(where: { $0.id == id }) {
            let look = LightDay.dragged(key, among: bulb.keys, at: minute, marks: marks)
            dragLook = look
            previewOn(bulb.id, look, at: minute)
        }
    }

    private func dropKey(_ id: UUID, bulb: LightDay.Bulb) {
        if let look = dragLook {
            edit { index in
                index.withKey(bulb.id, id) {
                    $0.on = look.on
                    $0.brightness = look.brightness
                    $0.xy = look.xy
                }
            }
        }
        dragging = nil
        dragLook = nil
        history.commit(undo, "Move Keyframe")
        endPreviewNow()
    }

    private func pasteLook(onto id: UUID, bulb: LightDay.Bulb) {
        guard let from = clip.key else { return }
        edit { index in
            index.withKey(bulb.id, id) {
                $0.on = from.on
                $0.brightness = from.brightness
                $0.x = from.x
                $0.y = from.y
            }
        }
        history.commit(undo, "Paste Color and Brightness")
    }

    private func deleteSelected() {
        guard let selection else { return }
        edit { $0[selection.bulb]?.keys.removeAll { $0.id == selection.key } }
        self.selection = nil
        history.commit(undo, "Delete Keyframe")
        endPreviewNow()
    }

    private func unlink(_ bulb: LightDay.Bulb) {
        let day = LightDay.keys(of: bulb, in: bulbs).map { k -> LightDay.Key in var k = k; k.id = UUID(); return k }
        edit {
            $0[bulb.id]?.keys = day
            $0[bulb.id]?.parent = nil
        }
        history.commit(undo, "Unlink Bulb")
    }

    private func togglePlay() {
        if playMinute != nil {
            playTask?.cancel()
            playMinute = nil
            appState.onEndLampPreview?()
            return
        }
        previewing = nil
        playTask = Task { @MainActor in
            let start = Date(), length = 10.0
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start) / length
                if t >= 1 { break }
                let minute = (nowMinute + t * Double(LightDay.day)).truncatingRemainder(dividingBy: Double(LightDay.day))
                playMinute = minute
                var states: [String: LightDay.State] = [:]
                for bulb in bulbs {
                    if let s = LightDay.state(LightDay.keys(of: bulb, in: bulbs), at: minute, marks: marks) { states[bulb.id] = s }
                }
                appState.onPreviewLamps?(states)
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            playMinute = nil
            appState.onEndLampPreview?()
        }
    }

    private func minute(atX x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let f = min(max(0, x / width), 0.9999)
        return LightDay.wrap(Layout.start + Int(f * Double(LightDay.day)))
    }

    // MARK: - Words

    static func time(_ minute: Int) -> String {
        let m = LightDay.wrap(minute), h = m / 60
        return String(format: "%d:%02d %@", h % 12 == 0 ? 12 : h % 12, m % 60, h < 12 ? "AM" : "PM")
    }

    static func hour(_ hour: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12) \(hour < 12 ? "AM" : "PM")"
    }

    static func markName(_ mark: LightDay.Mark) -> String {
        switch mark {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        case .darkest: return "Bedtime"
        }
    }

    static func anchorText(_ anchor: LightDay.Anchor?) -> String? {
        guard let anchor else { return nil }
        let name = markName(anchor.mark).lowercased()
        if anchor.offset == 0 { return "Follows \(name)" }
        let mins = abs(anchor.offset)
        let amount = mins >= 60 && mins % 60 == 0 ? "\(mins / 60) hr" : "\(mins) min"
        return "\(amount) \(anchor.offset < 0 ? "before" : "after") \(name)"
    }

    static func keyHelp(_ key: LightDay.Key, marks: LightDay.Marks) -> String {
        let level = key.on ? "\(Int(key.brightness.rounded()))%" : "Off"
        return "\(time(LightDay.minute(of: key, marks: marks))) · \(level)"
    }

    static func state(_ key: LightDay.Key) -> LightDay.State {
        .init(on: key.on, brightness: key.brightness, xy: key.xy)
    }

    static func color(_ s: LightDay.State) -> Color {
        guard s.on else { return Color(white: 0.2) }
        let c = LightDay.rgb(s.xy), d = LightDay.shade(brightness: s.brightness)
        return Color(red: c.r * d, green: c.g * d, blue: c.b * d)
    }
}

enum Layout {
    /// Between the window's edge and what's in it.
    static let edge: CGFloat = 28
    static let name: CGFloat = 130
    static let gap: CGFloat = 12
    static let bandHeight: CGFloat = 34
    static let linkedHeight: CGFloat = 12
    /// What shows of a row above and below its band.
    static let bandMargin: CGFloat = 5
    static let rowHeight: CGFloat = bandHeight + 2 * bandMargin
    static let rowGap: CGFloat = 8
    static let rowsPadding: CGFloat = 16

    static let cardCorner: CGFloat = 12
    static let cardPadding: CGFloat = 14
    /// The card's close button sits over the end of its first line.
    static let cardCloseRoom: CGFloat = 24
    static let cardLabel: CGFloat = 84
    static let iconButton: CGFloat = 22
    /// The colour wheel's height plus its padding.
    static let cardHeight: CGFloat = 144
    /// With the gap above it, so it comes out from behind the rows' own card.
    static let cardRoom: CGFloat = cardHeight + 2 * rowsPadding
    static let slide = 0.28

    /// Whether the rows fit in `height`: their card's padding, the marks and hours, and a row
    /// and a gap per bulb.
    static func rowsFit(_ rows: Int, in height: CGFloat) -> Bool {
        rowsPadding + cardPadding * 2 + 22 + 14 + rowGap * CGFloat(rows + 1) + rowHeight * CGFloat(rows) <= height
    }

    /// The axis starts at 5 AM, so the day reads left to right and the night
    /// isn't split in two at midnight.
    static let start = 5 * 60

    static func position(_ minute: Int) -> Double { position(Double(minute)) }
    static func position(_ minute: Double) -> Double {
        let day = Double(LightDay.day)
        return (minute - Double(start) + day).truncatingRemainder(dividingBy: day) / day
    }
}

/// The marks' labels, each over its spot on the day unless that would overlap
/// another. A `Layout` because it needs their widths before placing them, which
/// measuring in a first pass could only give after a frame in the wrong place.
private struct MarkLabels: SwiftUI.Layout {
    let spots: [Double]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = subviews.map { Double($0.sizeThatFits(.unspecified).width) }
        let centers = LightDay.spread(spots.map { $0 * Double(bounds.width) }, widths: widths, gap: 8, across: Double(bounds.width))
        for (view, x) in zip(subviews, centers) {
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .center, proposal: .unspecified)
        }
    }
}

/// Bulbs by id, so an edit reads as what it does.
struct BulbIndex {
    var bulbs: [LightDay.Bulb]

    subscript(id: String) -> LightDay.Bulb? {
        get { bulbs.first { $0.id == id } }
        set {
            guard let i = bulbs.firstIndex(where: { $0.id == id }), let newValue else { return }
            bulbs[i] = newValue
        }
    }

    mutating func withKey(_ bulb: String, _ key: UUID, _ apply: (inout LightDay.Key) -> Void) {
        guard let i = bulbs.firstIndex(where: { $0.id == bulb }),
              let k = bulbs[i].keys.firstIndex(where: { $0.id == key }) else { return }
        apply(&bulbs[i].keys[k])
    }
}

// MARK: - The band

/// A keyframe: its true colour, in a ring that fills with its brightness clockwise from the top.
/// The band is dimmed so the day reads at a glance, which leaves this as the one place the real
/// colour shows. The track and edge are dark because white alone vanishes on a pale band.
private struct KeyDot: View {
    let look: LightDay.State
    let selected: Bool

    var body: some View {
        let size: CGFloat = selected ? 26 : 22
        let line: CGFloat = selected ? 3 : 2.5
        let c = LightDay.rgb(look.xy)
        ZStack {
            Circle().fill(look.on ? Color(red: c.r, green: c.g, blue: c.b) : Color.black.opacity(0.6))
            Circle().inset(by: line / 2).stroke(.black.opacity(0.5), lineWidth: line)
            Circle().inset(by: line / 2).trim(from: 0, to: look.on ? look.brightness / 100 : 0)
                .rotation(.degrees(-90)).stroke(.white, lineWidth: line)
        }
        .frame(width: size, height: size)
        .background(Circle().stroke(.black.opacity(0.55), lineWidth: selected ? 1.5 : 0.75))
    }
}

/// One column per pixel, because a gradient with stops at the keyframes would be
/// a straight line in sRGB, which isn't where the bulb goes.
private struct Band: View {
    let keys: [LightDay.Key]
    let marks: LightDay.Marks
    let without: UUID?

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.06)))
            let columns = Int(size.width)
            guard columns > 0 else { return }
            for x in 0..<columns {
                let minute = (Double(Layout.start) + Double(x) / Double(columns) * Double(LightDay.day))
                    .truncatingRemainder(dividingBy: Double(LightDay.day))
                guard let s = LightDay.state(keys, at: minute, marks: marks, without: without), s.on else { continue }
                context.fill(Path(CGRect(x: CGFloat(x), y: 0, width: 1.5, height: size.height)), with: .color(LightsView.color(s)))
            }
        }
    }
}

// MARK: - The card's contents

/// A look on the card under the rows, a keyframe's or a bulb's right now. The two differ
/// only in the row saying which, so opening one after the other moves nothing.
private struct LookPanel<Identity: View>: View {
    let bulb: String
    let kind: String
    let look: LightDay.State
    let keptFor: String
    let change: ((inout LightDay.State) -> Void) -> Void
    let commit: () -> Void
    @ViewBuilder let identity: () -> Identity

    /// Each look's temperature from before the wheel took it off the whites.
    @State private var kept: [String: Int] = [:]

    var body: some View {
        HStack(spacing: 14) {
            ColorWheel(xy: look.xy, change: { xy in
                kept[keptFor] = LightDay.keptKelvin(leaving: look.xy, kept: kept[keptFor])
                change { $0.xy = xy }
            }, commit: commit)
                .frame(width: wheel, height: wheel)
                .disabled(!look.on)
                .dimmed(look.on)
            // Beside the wheel's curve the switch has no edge to sit against, so this is it.
            Divider()
            // Evenly down the wheel's height, so nothing piles up at the top of the card.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    // The switch is always the bulb: on or off at this keyframe, or now.
                    Toggle(bulb, isOn: Binding(get: { look.on }, set: { on in
                        change { $0.on = on }
                        commit()
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
                    Text(bulb)
                        .font(.headline)
                        .lineLimit(1)
                    Text(kind)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Layout.cardCloseRoom)
                Spacer(minLength: 0)
                identity()
                Spacer(minLength: 0)
                field("Brightness", value: look.on ? "\(Int(look.brightness.rounded()))%" : "Off") {
                    Slider(value: Binding(get: { look.brightness }, set: { b in adjust { $0.brightness = b } }), in: 0...100, onEditingChanged: edited)
                        .dimmed(look.on)
                        .allowsHitTesting(look.on)
                }
                .foregroundStyle(look.on ? .primary : .secondary)
                Spacer(minLength: 0)
                temperature
                    .allowsHitTesting(look.on)
            }
            .frame(height: wheel)
        }
        .font(.subheadline)
    }

    private var wheel: CGFloat { Layout.cardHeight - 2 * Layout.cardPadding }

    /// The sliders stay enabled while off, because `.disabled` draws them with no fill: "removing
    /// the filled bar looks kind of weird". So being off stops them here and with hit testing.
    private func adjust(_ apply: (inout LightDay.State) -> Void) {
        if look.on { change(apply) }
    }

    /// Dimmed for a colour that isn't a white, which has no temperature, with the slider
    /// staying where it was and the reason in place of a number. It can still be dragged,
    /// since that's the way back to a white.
    private var temperature: some View {
        let white = LightDay.hasTemperature(look.xy)
        return field("Temperature", value: !look.on ? "Off" : white ? "\(LightDay.kelvin(look.xy)) K" : "Color") {
            // Rounded here rather than with the slider's step, which draws a tick at
            // every step and made it look unlike Brightness.
            Slider(value: Binding(get: { Double(LightDay.sliderKelvin(look.xy, kept: kept[keptFor])) }, set: { k in
                adjust { $0.xy = LampBlend.xy(mirek: 1_000_000 / ((k / 50).rounded() * 50)) }
            }), in: LampBlend.lowestKelvin...6500, onEditingChanged: edited)
            .dimmed(white && look.on)
        }
        .foregroundStyle(white && look.on ? .primary : .secondary)
        .help(white || !look.on ? "" : "Only whites have a temperature, and this color isn't one. Drag to go back to a white.")
    }

    private func field<C: View>(_ label: String, value: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: Layout.cardLabel, alignment: .leading)
            control()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func edited(_ editing: Bool) { if !editing { commit() } }
}

/// A keyframe's time, which is what tells it from the bulb's others, so it sits right under
/// the name.
private struct KeyTimeRow: View {
    let key: LightDay.Key
    let marks: LightDay.Marks
    let change: ((inout LightDay.Key) -> Void) -> Void
    let commit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Time").frame(width: Layout.cardLabel, alignment: .leading)
            TimeField(label: "Time", time: timeBinding)
            if let text = LightsView.anchorText(key.anchor) {
                // Gives way first when the window is small, with the whole of it on hover.
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(text)
            }
            Spacer(minLength: 0)
        }
    }

    /// A typed time keeps the keyframe's look. Only a drag takes what's under it.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { LightDay.clockTime(LightDay.minute(of: key, marks: marks), on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                change {
                    $0.minute = m
                    $0.anchor = LightDay.snap(m, marks: marks)
                }
                commit()
            }
        )
    }
}

private extension View {
    /// The one ground for the rows and the card under them.
    func cardGround() -> some View {
        background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Layout.cardCorner))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cardCorner)
                    .strokeBorder(.primary.opacity(0.12))
            }
    }

    /// How a card's control looks when it isn't in use, the same whatever the reason.
    func dimmed(_ active: Bool) -> some View {
        tint(active ? nil : .gray)
            .opacity(active ? 1 : 0.5)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

/// Whether a bulb is on its schedule, and the way back when it isn't.
private struct HoldRow: View {
    let held: Bool
    let paused: Bool
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Right now").frame(width: Layout.cardLabel, alignment: .leading)
            if held {
                Text("Held until sunrise")
                    .foregroundStyle(.orange)
            } else {
                Text(paused ? "Paused" : "Following the schedule")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // There either way and only usable when held, so nothing moves as it starts.
            Button(action: back) {
                Text("Back to schedule").foregroundStyle(.orange)
            }
                .controlSize(.small)
                .hoverShade()
                .opacity(held ? 1 : 0)
                .allowsHitTesting(held)
        }
    }
}

/// Rename in place: Return or clicking away keeps the name, Escape drops it.
private struct RenameField: View {
    @State var name: String
    let done: (String) -> Void
    @FocusState private var focused: Bool

    init(name: String, done: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.done = done
    }

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { done(name) }
            .onExitCommand { done("") }
            .onChange(of: focused) { _, now in if !now { done(name) } }
    }
}

/// Any colour a bulb can take: hue around the rim, white at the centre.
private struct ColorWheel: View {
    let xy: LampBlend.XY
    let change: (LampBlend.XY) -> Void
    let commit: () -> Void

    private static let hues: [Color] = [.init(red: 1, green: 0, blue: 0), .init(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 0),
                                        .init(red: 0, green: 1, blue: 1), .init(red: 0, green: 0, blue: 1), .init(red: 1, green: 0, blue: 1),
                                        .init(red: 1, green: 0, blue: 0)]

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            let spot = LightDay.wheel(xy)
            let angle = spot.hue * 2 * .pi
            ZStack {
                Circle().fill(AngularGradient(colors: Self.hues, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .position(x: radius + cos(angle) * spot.saturation * radius, y: radius + sin(angle) * spot.saturation * radius)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        let x = drag.location.x - radius, y = drag.location.y - radius
                        change(LightDay.xy(hue: atan2(y, x) / (2 * .pi), saturation: hypot(x, y) / radius))
                    }
                    .onEnded { _ in commit() }
            )
        }
    }
}
