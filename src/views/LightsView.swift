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
/// click one for its settings. Right-click for copy, paste and linking.
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

    struct Selection: Equatable { var bulb: String; var key: UUID }
    struct Clip { var key: LightDay.Key?; var day: [LightDay.Key]? }
    struct Previewing { var look: LightDay.State; var minute: Int }

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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            marksHeader
                            ForEach(bulbs) { bulb in
                                row(bulb)
                                if selection?.bulb == bulb.id, let key = selectedKey {
                                    KeyDrawer(
                                        key: key,
                                        marks: marks,
                                        change: { change(key.id, $0) },
                                        commit: {
                                            history.commit(undo, "Change Keyframe")
                                            endPreviewNow()
                                        },
                                        delete: { deleteSelected() },
                                        close: { closeDrawer() }
                                    )
                                    .transition(.opacity)
                                }
                            }
                            hoursAxis
                        }
                        .padding(16)
                    }
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
        .onDisappear {
            playTask?.cancel()
            endPreviewNow()
        }
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
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 28)
            .transition(.opacity)
            Spacer()
            Button(playMinute == nil ? "Play the day" : "Stop", action: togglePlay)
                .disabled(bulbs.isEmpty)
            Button(appState.lampsFollow ? "Pause" : "Resume") {
                appState.lampsFollow.toggle()
                appState.save()
                appState.onLampsChanged?()
            }
            .disabled(appState.hueHost == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: previewing == nil)
    }

    private func previewBadge(_ p: Previewing) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Self.color(p.look))
                .frame(width: 12, height: 12)
            Text("\(p.look.on ? "\(Int(p.look.brightness.rounded()))%" : "Off") at \(Self.time(p.minute))")
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

    private var statusLine: String {
        if !appState.lampStatus.hasPrefix("Paired"), appState.hueHost != nil { return appState.lampStatus }
        return "Paused. The bulbs stay as they are until you resume."
    }

    private var unpaired: some View {
        VStack(spacing: 10) {
            Text("Pair with your Hue Bridge to see your bulbs here.")
                .foregroundStyle(.secondary)
            Button("Pair Hue Bridge") { appState.onPairLamps?() }
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
                        .foregroundStyle(.tertiary)
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
        return HStack(spacing: Layout.gap) {
            name(bulb)
                .frame(width: Layout.name, height: Layout.bandHeight + 8, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { rowMenu(bulb) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Band(keys: keys, marks: marks, without: dragging)
                        .frame(height: linked ? Layout.linkedHeight : Layout.bandHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(linked ? nil : SpatialTapGesture().onEnded { addKey(bulb, at: $0.location.x, width: geo.size.width) })
                        .contextMenu { bandMenu(bulb, width: geo.size.width) }
                        .onContinuousHover { phase in
                            if case .active(let p) = phase { hoverX = p.x }
                        }
                    Rectangle()
                        .fill(.primary.opacity(0.85))
                        .frame(width: 1.5, height: Layout.bandHeight + 8)
                        .offset(x: geo.size.width * Layout.position(lineMinute))
                        .allowsHitTesting(false)
                    if !linked {
                        ForEach(keys) { key in
                            dot(key, bulb: bulb, width: geo.size.width)
                        }
                    }
                }
            }
            .frame(height: Layout.bandHeight + 8)
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
                Text(bulb.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .background(selection?.bulb == bulb.id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onTapGesture { renaming = bulb.id }
        }
    }

    private func dot(_ key: LightDay.Key, bulb: LightDay.Bulb, width: CGFloat) -> some View {
        let at = LightDay.minute(of: key, marks: marks)
        let look = dragging == key.id ? (dragLook ?? Self.state(key)) : Self.state(key)
        let selected = selection?.key == key.id
        return Circle()
            .fill(Self.color(look))
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.white, lineWidth: selected ? 2.5 : 1.5))
            .frame(width: selected ? 15 : 13, height: selected ? 15 : 13)
            .contentShape(Circle().inset(by: -4))
            .position(x: width * Layout.position(at), y: (Layout.bandHeight + 8) / 2)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { moveKey(key.id, bulb: bulb, to: $0.location.x, width: width) }
                    .onEnded { _ in dropKey(key.id, bulb: bulb) }
            )
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { toggle(Selection(bulb: bulb.id, key: key.id)) } }
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
        guard let selection else { return nil }
        return bulbs.first { $0.id == selection.bulb }?.keys.first { $0.id == selection.key }
    }

    private func edit(_ change: (inout BulbIndex) -> Void) {
        var index = BulbIndex(bulbs: bulbs)
        change(&index)
        appState.lights = index.bulbs
    }

    private func toggle(_ s: Selection) {
        if selection == s { closeDrawer() } else {
            history.commit(undo, "Change Keyframe")
            selection = s
        }
    }

    private func closeDrawer() {
        history.commit(undo, "Change Keyframe")
        withAnimation(.easeOut(duration: 0.15)) { selection = nil }
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
        previewing = Previewing(look: look, minute: minute)
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
        withAnimation(.easeOut(duration: 0.15)) { selection = Selection(bulb: bulb.id, key: key.id) }
    }

    /// While dragged a keyframe shows what's under it, and on drop it takes that.
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
        if let look = LightDay.state(bulb.keys, at: Double(minute), marks: marks, without: id) {
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
        case .darkest: return "Darkest"
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
    static let name: CGFloat = 130
    static let gap: CGFloat = 12
    static let bandHeight: CGFloat = 22
    static let linkedHeight: CGFloat = 10
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

// MARK: - The drawer

/// A keyframe's settings, opening under its row. The header is also the time
/// setting and the on/off, so they take no rows of their own.
private struct KeyDrawer: View {
    let key: LightDay.Key
    let marks: LightDay.Marks
    let change: ((inout LightDay.Key) -> Void) -> Void
    let commit: () -> Void
    let delete: () -> Void
    let close: () -> Void

    private static let colors: [(name: String, x: Double, y: Double)] = [
        ("Amber", 0.5469, 0.4106), ("Coral", 0.62, 0.36), ("Red", 0.675, 0.322), ("Pink", 0.42, 0.22),
        ("Violet", 0.25, 0.10), ("Blue", 0.16, 0.06), ("Teal", 0.17, 0.35), ("Green", 0.21, 0.65),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .controlSize(.small)
                Toggle("On", isOn: Binding(get: { key.on }, set: { on in
                    change { $0.on = on }
                    commit()
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                if let text = LightsView.anchorText(key.anchor) {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            field("Brightness", value: "\(Int(key.brightness.rounded()))%") {
                Slider(value: Binding(get: { key.brightness }, set: { b in change { $0.brightness = b } }), in: 0...100, onEditingChanged: edited)
            }
            field("White", value: LightDay.kelvin(key.xy).map { "\($0) K" } ?? "Color") {
                Slider(value: Binding(get: { Double(LightDay.kelvin(key.xy) ?? 2700) }, set: { k in
                    change { $0.xy = LampBlend.xy(mirek: 1_000_000 / k) }
                }), in: LampBlend.lowestKelvin...6500, step: 50, onEditingChanged: edited)
            }
            HStack(spacing: 8) {
                Text("Color")
                    .frame(width: 72, alignment: .leading)
                ForEach(Self.colors, id: \.name) { c in
                    Button {
                        change {
                            $0.x = c.x
                            $0.y = c.y
                        }
                        commit()
                    } label: {
                        let rgb = LightDay.rgb(.init(x: c.x, y: c.y))
                        Circle()
                            .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(c.name)
                }
                Spacer()
                Button("Delete Keyframe", action: delete)
                    .controlSize(.small)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func field<C: View>(_ label: String, value: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 72, alignment: .leading)
            control()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func edited(_ editing: Bool) { if !editing { commit() } }

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
