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
        finish(from: before, name)
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
                history.finish(from: current, "Undo or Redo \(name)")
            }
        }
    }

    private func finish(from before: [LightDay.Bulb]?, _ name: String) {
        guard let state else { return }
        state.save()
        LightsLog.write(before: before, after: state.lights, change: name)
        for bulb in state.lights ?? [] {
            if let old = before?.first(where: { $0.id == bulb.id }), old.name != bulb.name {
                state.onRenameBulb?(bulb.deviceID, bulb.name)
            }
        }
        state.onLampsChanged?()
    }
}

/// One row per bulb across the day, the band being what the bulb does: its colour, with
/// its brightness on the keyframes' rings. Click a band for a keyframe, drag one to move it,
/// click one for its settings on the card that comes down below, or click a bulb's
/// name to change it right now. Right-click for copy, paste and linking.
struct LightsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.undoManager) private var undo
    @StateObject private var history = LightsHistory()

    @State private var selection: Selection?
    @State private var clip: Clip = .init()
    @State private var renaming: String?
    @State private var playMinute: Double?
    @Environment(\.colorScheme) private var scheme
    @State private var playTask: Task<Void, Never>?
    @State private var previewing: Previewing?
    @State private var dragStart: (id: UUID, anchor: LightDay.Anchor?)?
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
            if selection == nil, !appState.movingKeyframe { history.seen(new) }
        }
        .onChange(of: shown) { _, new in if let new { lastShown = new } }
        .onChange(of: selection != nil) { _, selected in slideCard(open: selected) }
        // A delete from the right-click menu, Paste Day or an undo. A right-click leaves the card
        // open, and the row is what's left of where that keyframe was.
        .onChange(of: keyframeGone) { _, gone in
            if gone, let selection { showRow(selection.bulb) }
        }
        .onDisappear {
            playTask?.cancel()
            endPreviewNow()
            appState.movingKeyframe = false
        }
    }

    private var lightsAndCard: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Whether they scroll is settled by the room they'd have with the card out, and
                // that's the scroll view's height either way. A scroll view resized by the
                // slide shows a scroll bar from each frame's rounding. A ViewThatFits here
                // settles it without that, but the card then jumps open instead of sliding.
                Group {
                    if Layout.rowsFit(bulbs.count, in: geo.size.height - Layout.cardRoom) {
                        rows
                    } else {
                        ScrollView { rows }
                            .frame(height: geo.size.height - Layout.cardRoom)
                    }
                }
                .zIndex(1)
                // Anchored at its bottom in a frame that grows, so it comes down from behind
                // the rows and they never move. Shown a corner's height above that frame too, behind
                // the rows, where it fills the rows' corners while they round.
                card
                    .frame(height: cardOpen ? Layout.cardRoom : 0, alignment: .bottom)
                    .mask(alignment: .top) { Rectangle().padding(.top, -Layout.cardCorner) }
                    .allowsHitTesting(cardOpen)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Layout.rowGap) {
            marksHeader
            ForEach(bulbs) { row($0) }
            hoursAxis
        }
        .padding(Layout.cardPadding)
        .cardGround(bottom: cardOpen ? 0 : Layout.cardCorner)
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
        if show.key != nil { return "Color Key" }
        guard let bulb = bulbs.first(where: { $0.id == show.bulbID }) else { return "" }
        if let parent = bulb.parent { return "Follows \(bulbs.first { $0.id == parent }?.name ?? "another bulb")" }
        return bulb.keys.count == 1 ? "1 Color Key" : "\(bulb.keys.count) Color Keys"
    }

    /// What a bulb's card starts from: its hold, or the lamp as last read, or where the
    /// day has it until that read comes back.
    private func rightNow(_ id: String) -> LightDay.State {
        appState.lampNow(id, read: lampsNow, at: nowMinute)
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
                if show.key != nil { history.commit(undo, "Change Color Key") }
                endPreviewNow()
            }
        ) {
            if let key = show.key {
                KeyTimeRow(key: key, marks: marks, change: { change(key.id, $0) }, commit: {
                    history.commit(undo, "Change Color Key")
                    endPreviewNow()
                })
            } else {
                HoldRow(held: holdOwner(show.bulbID) != nil, paused: !appState.lampsFollow, back: { returnToSchedule(show.bulbID) })
            }
        }
        .padding(Layout.cardPadding)
        .frame(height: Layout.cardHeight)
        .frame(maxWidth: .infinity)
        // Its ground reaches a corner's height up behind the rows, so whatever their corners are
        // doing as it slides, there's drawer behind them rather than a gap.
        .padding(.top, Layout.cardCorner)
        .cardGround(top: 0)
        .padding(.top, -Layout.cardCorner)
        .overlay(alignment: .topTrailing) {
            Button(action: deselect) {
                Image(systemName: "chevron.up")
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
                        .foregroundStyle(Layout.dim)
                } else {
                    Label {
                        Text(statusLine)
                    } icon: {
                        if isPaused { Image(systemName: "pause.fill") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(isPaused ? AnyShapeStyle(.orange) : AnyShapeStyle(Layout.dim))
                }
            }
            .frame(height: 28)
            .transition(.opacity)
            Spacer()
            if appState.keychainDeclined {
                Button("Allow Keychain Access") { appState.onAllowKeychain?() }
                    .hoverShade()
            }
            // Here as well as on the card, since a hold is easy to forget once the card is shut.
            if !appState.holds.isEmpty {
                Button(action: returnAllToSchedule) {
                    Text("Return to schedule").foregroundStyle(.orange)
                }
                .hoverShade()
                .transition(.opacity)
            }
            // Orange text while the lights are off the day, as Return to schedule and the menu bar's
            // sun are: one color for one state, and a filled button shouted over the rest.
            Button(action: togglePlay) {
                Text(playMinute == nil ? "Play the day" : "Stop")
                    .orange(playMinute != nil)
            }
                .disabled(bulbs.isEmpty)
                .hoverShade()
            Button(action: togglePause) {
                Text(appState.lampsFollow ? "Pause" : "Resume")
                    .orange(isPaused)
            }
            .disabled(appState.hueHost == nil)
            .hoverShade()
        }
        .padding(.horizontal, Layout.edge)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: previewing == nil)
        .animation(.easeOut(duration: 0.15), value: appState.holds.isEmpty)
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

    private var isPaused: Bool { appState.lampsPaused }

    private func togglePause() { appState.toggleLampsFollow() }

    private var statusLine: String {
        if !appState.lampStatus.hasPrefix("Paired"), appState.hueHost != nil { return appState.lampStatus }
        return "Paused. The bulbs stay as they are until you resume."
    }

    private var unpaired: some View {
        VStack(spacing: 10) {
            Text("Pair with your Hue Bridge to see your bulbs here.")
                .foregroundStyle(Layout.dim)
            Button("Pair Hue Bridge") { appState.onPairLamps?() }
                .hoverShade()
            Text(appState.lampStatus)
                .font(.caption)
                .foregroundStyle(Layout.dim)
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
                            .foregroundStyle(Layout.dim)
                            .fixedSize()
                    }
                }
                // Where each mark really is, since a label may have been pushed off it.
                GeometryReader { geo in
                    ForEach(LightDay.Mark.allCases, id: \.self) { mark in
                        Rectangle()
                            .fill(Layout.dim)
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
                        .foregroundStyle(Layout.dim)
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
                .onHover { inside in
                    withAnimation(.easeOut(duration: 0.1)) {
                        hoveredName = inside ? bulb.id : (hoveredName == bulb.id ? nil : hoveredName)
                    }
                }
                .contextMenu { rowMenu(bulb) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Band(keys: keys, marks: marks)
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
                                .frame(width: Layout.scrubberLine, height: Layout.rowHeight + Layout.rowGap)
                                .offset(x: geo.size.width * Layout.position(lineMinute) - Layout.scrubberLine / 2)
                        }
                        .overlay(alignment: .leading) {
                            if bulb.id == bulbs.last?.id {
                                // Solid, because `.primary` is 85% on macOS and the line showed through to its centre.
                                Circle()
                                    .fill(scheme == .dark ? Color.white : Color.black)
                                    .frame(width: Layout.scrubberHead, height: Layout.scrubberHead)
                                    .offset(x: geo.size.width * Layout.position(lineMinute) - Layout.scrubberHead / 2, y: (Layout.rowHeight + Layout.rowGap) / 2)
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
                .fill(.primary.opacity(selected ? 0.08 : hoveredName == bulb.id ? 0.12 : 0))
                .padding(.trailing, -Layout.bandMargin)
                .animation(.easeOut(duration: 0.15), value: selected)
        }
    }

    /// Where the pointer last was over a band, for the band's right-click menu.
    @State private var hoverX: CGFloat = 0
    /// The bulb whose name is under the pointer: its whole row shades, as a click there lights the
    /// whole row.
    @State private var hoveredName: String?

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
                            .foregroundStyle(Layout.dim)
                            .lineLimit(1)
                    }
                }
                if bulb.parent != nil {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(Layout.dim)
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
        let selected = selection?.key == key.id
        return KeyDot(look: Self.state(key), selected: selected)
            .contentShape(Circle().inset(by: -1))
            .position(x: width * Layout.position(at), y: Layout.rowHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { moveKey(key.id, bulb: bulb, to: $0.location.x, width: width) }
                    .onEnded { _ in dropKey() }
            )
            .onTapGesture { toggle(Selection(bulb: bulb.id, key: key.id)) }
            .contextMenu { keyMenu(key, bulb: bulb) }
            .help(Self.keyHelp(key, marks: marks))
    }

    // MARK: - Menus

    @ViewBuilder
    private func keyMenu(_ key: LightDay.Key, bulb: LightDay.Bulb) -> some View {
        Button("Copy Color Key") { clip.key = key }
        Button("Paste Color Key") { pasteLook(onto: key.id, bulb: bulb) }
            .disabled(clip.key == nil)
        Divider()
        Button("Delete Color Key") { deleteKey(key.id, of: bulb.id) }
    }

    @ViewBuilder
    private func bandMenu(_ bulb: LightDay.Bulb, width: CGFloat) -> some View {
        Button("Paste Color Key at \(Self.time(minute(atX: hoverX, width: width)))") {
            guard var key = clip.key else { return }
            key.id = UUID()
            key.minute = minute(atX: hoverX, width: width)
            key.anchor = LightDay.anchor(like: key.anchor, at: key.minute, marks: marks, snapping: true)
            if let a = key.anchor, a.offset == 0 { key.minute = marks.minute(of: a.mark) }
            edit { $0[bulb.id]?.keys.append(key) }
            history.commit(undo, "Paste Color Key")
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
                        // Its keyframes are no longer what it does, so its own card stands in.
                        if selection?.bulb == bulb.id, selection?.key != nil { showRow(bulb.id) }
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
            history.commit(undo, "Change Color Key")
            show(s)
        }
    }

    private func show(_ s: Selection) {
        // Opening takes the card's slide. A dot with an animation of its own would
        // leave its row behind during that slide.
        if selection == nil { selection = s } else { withAnimation(.easeOut(duration: 0.15)) { selection = s } }
    }

    private var keyframeGone: Bool { selection?.key != nil && selectedKey == nil }

    private func showRow(_ id: String) {
        show(Selection(bulb: id, key: nil))
        readLampsNow()
    }

    private func readLampsNow() {
        Task { if let read = try? await appState.onReadLamps?() { lampsNow = read } }
    }

    /// The card for the bulb itself, from what the lamp is doing now.
    private func selectBulb(_ id: String) {
        toggle(Selection(bulb: id, key: nil))
        guard selection?.key == nil, selection?.bulb == id else { return }
        readLampsNow()
    }

    private func holdOwner(_ id: String) -> String? { appState.lampHoldOwner(id) }

    private func hold(_ id: String, _ apply: (inout LightDay.State) -> Void) {
        let set = appState.holdLamp(id, from: rightNow(id), apply)
        // Paused, nothing holds it, so this is where the card learns where the bulb is.
        if !appState.lampsFollow { lampsNow[id] = set }
    }

    /// From a follower too, whose button would otherwise do nothing while the hold it's under is another bulb's.
    private func returnToSchedule(_ id: String) {
        previewing = nil
        appState.returnLampsToSchedule(id) { lampsNow = [:] }
    }

    /// The rows' corners square as the drawer comes out and round as it goes in, in the same
    /// animation, so both end together. Opening waits a frame, so the card's values land before
    /// the slide rather than sliding with it.
    private func slideCard(open: Bool) {
        guard open else {
            withAnimation(.easeOut(duration: Layout.slide)) { cardOpen = false }
            return
        }
        DispatchQueue.main.async {
            guard selection != nil else { return }
            withAnimation(.easeOut(duration: Layout.slide)) { cardOpen = true }
        }
    }

    private func returnAllToSchedule() {
        previewing = nil
        appState.returnLampsToSchedule { lampsNow = [:] }
    }

    private func deselect() {
        guard selection != nil else { return }
        history.commit(undo, "Change Color Key")
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
        let key = LightDay.Key(minute: at, anchor: LightDay.anchorForNew(at, marks: marks), on: look?.on ?? true,
                               brightness: look?.brightness ?? 50, x: look?.xy.x ?? warm.x, y: look?.xy.y ?? warm.y)
        edit { $0[bulb.id]?.keys.append(key) }
        history.commit(undo, "Add Color Key")
        // As clicking from one key to another does: with the card open its sliders glide to the
        // new key's values, and a closed one opens already showing them.
        show(Selection(bulb: bulb.id, key: key.id))
    }

    /// Only the time moves, so the band reshapes around the keyframe. A colour between two keyframes is
    /// what a new one is for. The bulbs wait for the drop, as scrubbing past noon at night would flood the room.
    private func moveKey(_ id: UUID, bulb: LightDay.Bulb, to x: CGFloat, width: CGFloat) {
        let at = minute(atX: x, width: width)
        // The rule it had when the drag began, so passing near a mark on the way doesn't change it.
        if dragStart?.id != id { dragStart = (id, bulb.keys.first { $0.id == id }?.anchor) }
        let anchor = LightDay.moved(dragStart?.anchor, to: at, marks: marks, snapping: true)
        let minute = anchor.flatMap { $0.offset == 0 ? marks.minute(of: $0.mark) : nil } ?? at
        appState.movingKeyframe = true
        edit { index in
            index.withKey(bulb.id, id) {
                $0.minute = minute
                $0.anchor = anchor
            }
        }
        if let key = bulb.keys.first(where: { $0.id == id }) {
            previewing = Previewing(bulb: bulb.name, look: Self.state(key), minute: minute)
        }
    }

    private func dropKey() {
        previewing = nil
        dragStart = nil
        // Before the save, whose tick takes the bulb to the new day at the usual fade. Ending a
        // preview here would rush it there in half a second, with nothing to come back from.
        appState.movingKeyframe = false
        history.commit(undo, "Move Color Key")
    }

    private func pasteLook(onto id: UUID, bulb: LightDay.Bulb) {
        guard let from = clip.key else { return }
        edit { index in
            index.withKey(bulb.id, id) {
                $0.on = from.on
                $0.brightness = from.brightness
                $0.x = from.x
                $0.y = from.y
                // Its rule too, at this keyframe's own time: fixed, or after or before a mark.
                $0.minute = LightDay.minute(of: $0, marks: marks)
                $0.anchor = LightDay.anchor(like: from.anchor, at: $0.minute, marks: marks, snapping: false)
            }
        }
        history.commit(undo, "Paste Color Key")
    }

    private func deleteKey(_ id: UUID, of bulb: String) {
        edit { $0[bulb]?.keys.removeAll { $0.id == id } }
        history.commit(undo, "Delete Color Key")
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

    /// In title case, as menu items are; "hr" and "min" stay lowercase as abbreviations.
    static func anchorText(_ anchor: LightDay.Anchor?) -> String? {
        guard let anchor else { return nil }
        let name = markName(anchor.mark)
        if anchor.offset == 0 { return "At \(name)" }
        let mins = abs(anchor.offset)
        let amount = [mins / 60 > 0 ? "\(mins / 60) hr" : nil, mins % 60 > 0 ? "\(mins % 60) min" : nil]
            .compactMap { $0 }.joined(separator: " ")
        return "\(amount) \(anchor.offset < 0 ? "Before" : "After") \(name)"
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
    /// Every grey text, in the window and the popup. A fixed grey, the one the system's secondary
    /// shows in the window (about 6:1 there): on the popup's glass the system's secondary came out
    /// at 3.2:1, under the 4.5:1 small text needs, and a translucent white was dimmer in the window.
    static let dim = Color(nsColor: NSColor(name: nil) { look in
        look.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.42, alpha: 1)
    })
    /// Between the window's edge and what's in it.
    static let edge: CGFloat = 28
    static let name: CGFloat = 130
    static let gap: CGFloat = 12
    static let bandHeight: CGFloat = 34
    static let linkedHeight: CGFloat = 12
    /// What shows of a row above and below its band.
    static let bandMargin: CGFloat = 8
    static let rowHeight: CGFloat = bandHeight + 2 * bandMargin
    static let rowGap: CGFloat = 8
    static let rowsPadding: CGFloat = 16
    /// Views land on whole pixels, so a line and a head share a centre only when both are odd in
    /// pixels or both even. At 2x these are 3 and 19; a head of 9 sat half a pixel off the line.
    static let scrubberLine: CGFloat = 1.5
    static let scrubberHead: CGFloat = 9.5

    static let cardCorner: CGFloat = 12
    static let cardTint: Double = 0.09
    static let cardPadding: CGFloat = 14
    /// The card's close button sits over the end of its first line.
    static let cardCloseRoom: CGFloat = 24
    static let cardLabel: CGFloat = 84
    static let iconButton: CGFloat = 22
    /// The colour wheel's height plus its padding.
    static let cardHeight: CGFloat = 144
    /// Hung from the rows' card as a drawer, with room below it.
    static let cardRoom: CGFloat = cardHeight + rowsPadding
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
        let size: CGFloat = selected ? 24 : 20
        let line = size * 0.114
        let c = LightDay.rgb(look.xy)
        ZStack {
            Circle().fill(Color(red: c.r, green: c.g, blue: c.b))
            // Together, so the grey is one grey where the slash crosses the ring.
            ZStack {
                Circle().inset(by: line / 2).stroke(.black, lineWidth: line)
                // Past the rim, or it reads as a crossed-out circle rather than ∅.
                if !look.on { Capsule().fill(.black).frame(width: line, height: size * 1.3).rotationEffect(.degrees(45)) }
            }
            .compositingGroup()
            .opacity(0.5)
            if look.on {
                Circle().inset(by: line / 2).trim(from: 0, to: look.brightness / 100)
                    .rotation(.degrees(-90)).stroke(.white, lineWidth: line)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().stroke(.black.opacity(0.55), lineWidth: selected ? 1.5 : 0.75))
        .dimmed(look.on)
    }
}

/// One column per pixel, because a gradient with stops at the keyframes would be
/// a straight line in sRGB, which isn't where the bulb goes.
private struct Band: View {
    let keys: [LightDay.Key]
    let marks: LightDay.Marks

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.06)))
            let columns = Int(size.width)
            guard columns > 0 else { return }
            for x in 0..<columns {
                let minute = (Double(Layout.start) + Double(x) / Double(columns) * Double(LightDay.day))
                    .truncatingRemainder(dividingBy: Double(LightDay.day))
                guard var s = LightDay.state(keys, at: minute, marks: marks) else { continue }
                // Off draws as the dimmest the bulb goes, in its colour, so the fade into it doesn't
                // stop at a hard edge.
                if !s.on { s = .init(on: true, brightness: 0, xy: s.xy) }
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
                        .foregroundStyle(Layout.dim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Layout.cardCloseRoom)
                Spacer(minLength: 0)
                identity()
                Spacer(minLength: 0)
                field("Brightness", value: "\(Int(look.brightness.rounded()))%") {
                    Slider(value: Binding(get: { look.brightness }, set: { b in adjust { $0.brightness = b } }), in: 0...100, onEditingChanged: edited)
                        .dimmed(look.on)
                        .allowsHitTesting(look.on)
                }
                .foregroundStyle(look.on ? Color.primary : Layout.dim)
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

    /// A color that isn't a white has no temperature: the bar goes grey, the slider stays where
    /// it was, and the reason is in place of a number.
    private var temperature: some View {
        let white = LightDay.hasTemperature(look.xy)
        return field("Temperature", value: white ? "\(LightDay.kelvin(look.xy)) K" : "Color") {
            // Rounded here rather than with the slider's step, which draws a tick at
            // every step and made it look unlike Brightness.
            Slider(value: Binding(get: { Double(LightDay.sliderKelvin(look.xy, kept: kept[keptFor])) }, set: { k in
                adjust { $0.xy = LampBlend.xy(mirek: 1_000_000 / ((k / 50).rounded() * 50)) }
            }), in: LampBlend.lowestKelvin...6500, onEditingChanged: edited)
            // A color greys only the bar: the knob stays white, since dragging it is the way
            // back to a white. Off dims the whole slider, as it does Brightness. One tint for
            // both cases: an inner .tint(nil) overrode dimmed's grey and left off whites blue.
            .tint(white && look.on ? nil : .gray)
            .dimmed(look.on)
        }
        .foregroundStyle(white && look.on ? Color.primary : Layout.dim)
        .help(white || !look.on ? "" : "Only whites have a temperature, and this color isn't one. Drag to go back to a white.")
    }

    private func field<C: View>(_ label: String, value: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: Layout.cardLabel, alignment: .leading)
            control()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Layout.dim)
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
            // A popup, so it reads as a setting to pick from rather than a caption.
            PopUp(items: [Self.fixedText] + choices.map { LightsView.anchorText($0) ?? "" },
                  selected: key.anchor.flatMap { choices.firstIndex(of: $0).map { $0 + 1 } } ?? 0) { i in
                anchorBinding.wrappedValue = i == 0 ? nil : choices[i - 1]
            }
            // One width for every choice, so the button and its caret don't move as it changes.
            .controlSize(.small)
            .frame(width: Self.menuWidth)
            .fixedSize(horizontal: false, vertical: true)
            .help(caption)
            Spacer(minLength: 0)
        }
    }

    /// "Every day" went unsaid: every color key repeats daily.
    private static let fixedText = "At This Time"
    /// The widest a choice can read, with room for the caret.
    private static let menuWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        let widest = [fixedText] + ["Sunrise", "Sunset", "Bedtime"].flatMap { ["00 hr 00 min Before \($0)", "00 hr 00 min After \($0)"] }
        return ceil(widest.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 150) + 40
    }()
    private var caption: String { LightsView.anchorText(key.anchor) ?? Self.fixedText }

    /// The marks either side of the keyframe, and its own anchor if the day has moved those since.
    private var choices: [LightDay.Anchor] {
        let near = LightDay.choices(LightDay.minute(of: key, marks: marks), marks: marks)
        guard let own = key.anchor, !near.contains(own) else { return near }
        return near + [own]
    }

    private var anchorBinding: Binding<LightDay.Anchor?> {
        Binding(
            get: { key.anchor },
            set: { anchor in
                let m = LightDay.minute(of: key, marks: marks)
                change {
                    $0.minute = m
                    $0.anchor = anchor
                }
                commit()
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { LightDay.clockTime(LightDay.minute(of: key, marks: marks), on: Date()) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                change {
                    $0.minute = m
                    $0.anchor = LightDay.moved($0.anchor, to: m, marks: marks, snapping: false)
                }
                commit()
            }
        )
    }
}

private extension View {
    /// The one ground for the rows and the card under them.
    /// On the window's own ground, so the drawer tucked under the rows can't show through as a
    /// lighter band. That ground is darker than the window's real one, which lets the desktop
    /// through, so the tint is stronger than a see-through card's to stand out as much.
    func cardGround(top: CGFloat = Layout.cardCorner, bottom: CGFloat = Layout.cardCorner) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top)
        return background(.primary.opacity(Layout.cardTint), in: shape)
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(.primary.opacity(0.12)) }
    }

    /// Only when on: a set color otherwise would keep a disabled button from greying.
    @ViewBuilder func orange(_ on: Bool) -> some View {
        if on { foregroundStyle(.orange) } else { self }
    }

    /// How a card's control looks when it isn't in use, the same whatever the reason.
    func dimmed(_ active: Bool) -> some View {
        // The animation is kept to the opacity: one on the whole view carried every other change
        // made with it, so a card opening on a lit color key after an off one slid its sliders.
        tint(active ? nil : .gray)
            .animation(.easeOut(duration: 0.15)) { $0.opacity(active ? 1 : 0.5) }
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
                    .foregroundStyle(Layout.dim)
            }
            Spacer(minLength: 8)
            // There either way and only usable when held, so nothing moves as it starts.
            Button(action: back) {
                Text("Return to schedule").foregroundStyle(.orange)
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
