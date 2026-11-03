import SwiftUI

/// Where the sun is worked out for, confirmed by looking at it: a dot on a map and
/// the times that follow from it. Search for a town, or click or drag to correct it.
/// Not Location Services, because a sunset needs a rough place and nobody has to give
/// up a precise one for it.
struct LocationSection: View {
    @EnvironmentObject var appState: AppState
    /// Where a drag is, so the map follows it and everything else waits for the drop.
    @State private var dragged: RoomLight.Place?
    @StateObject private var search = PlaceSearch()
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searching: Bool

    private var shown: (latitude: Double, longitude: Double)? {
        if let dragged { return (Double(dragged.latitude), Double(dragged.longitude)) }
        return SunClock.location()
    }

    private var isPicked: Bool {
        appState.place?.zone == TimeZone.autoupdatingCurrent.identifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("The sunrise and sunset everything follows are worked out for this spot. Roughly is enough. What you type goes to Apple to find it; the spot stays on this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            searchField
            // Over the map rather than between the two, so nothing moves as the list comes and goes.
            map.overlay(alignment: .top) { suggestions }
            // A set height, so the section holds still as the button comes and goes.
            HStack {
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isPicked, dragged == nil {
                    Button("Use My Time Zone") { pick(nil) }
                        .controlSize(.small)
                }
            }
            .frame(height: 22)
        }
    }

    private var searchField: some View {
        TextField("Search for your town", text: $query)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .focused($searching)
            .onChange(of: query) {
                highlighted = 0
                search.find(query)
            }
            .onSubmit { choose(highlighted) }
            .onKeyPress(.downArrow) {
                highlighted = min(highlighted + 1, max(search.results.count - 1, 0))
                return .handled
            }
            .onKeyPress(.upArrow) {
                highlighted = max(highlighted - 1, 0)
                return .handled
            }
            .onKeyPress(.escape) {
                guard !query.isEmpty else { return .ignored }
                query = ""
                return .handled
            }
    }

    @ViewBuilder private var suggestions: some View {
        if !query.isEmpty, !search.results.isEmpty || search.problem != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let problem = search.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                ForEach(Array(search.results.enumerated()), id: \.offset) { index, result in
                    Button { choose(index) } label: {
                        HStack(spacing: 6) {
                            Text(result.title)
                            Text(result.subtitle).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(index == highlighted ? Color.primary.opacity(0.1) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { highlighted = index } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }

    private func choose(_ index: Int) {
        guard search.results.indices.contains(index) else { return }
        let result = search.results[index]
        Task {
            guard let at = await search.coordinate(of: result) else { return }
            pick(RoomLight.Place(near: at.latitude, at.longitude, zone: TimeZone.autoupdatingCurrent.identifier, name: result.title))
            searching = false
        }
    }

    private var map: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.05)))
                    var path = Path()
                    for land in WorldMap.land {
                        let points = land.map { corner -> CGPoint in
                            let s = WorldMap.spot(latitude: corner.lat, longitude: corner.lon)
                            return CGPoint(x: s.x * size.width, y: s.y * size.height)
                        }
                        path.addLines(points)
                        path.closeSubpath()
                    }
                    context.fill(path, with: .color(.primary.opacity(0.22)))
                }
                if let shown {
                    let s = WorldMap.spot(latitude: shown.latitude, longitude: shown.longitude)
                    Circle()
                        .fill(Color.accentColor)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 13, height: 13)
                        .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragged = place(at: $0.location, in: geo.size) }
                    .onEnded {
                        pick(place(at: $0.location, in: geo.size))
                        dragged = nil
                    }
            )
        }
        .aspectRatio(WorldMap.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func place(at p: CGPoint, in size: CGSize) -> RoomLight.Place {
        WorldMap.place(x: p.x, y: p.y, width: size.width, height: size.height, zone: TimeZone.autoupdatingCurrent.identifier)
    }

    private func pick(_ place: RoomLight.Place?) {
        query = ""
        appState.place = place
        appState.save()
        appState.onLampsChanged?()
    }

    private var readout: String {
        guard let shown else { return "Search for your town, or click your part of the world." }
        let lat = "\(abs(Int(shown.latitude.rounded())))° \(shown.latitude < 0 ? "S" : "N")"
        let lon = "\(abs(Int(shown.longitude.rounded())))° \(shown.longitude < 0 ? "W" : "E")"
        guard dragged == nil, let sun = SunClock.sun() else { return "\(lat), \(lon)" }
        let place = isPicked ? appState.place?.name ?? "\(lat), \(lon)" : "\(lat), \(lon)"
        return "\(place) · Today: sunrise \(LightsView.time(Int(sun.sunrise.rounded()))), sunset \(LightsView.time(Int(sun.sunset.rounded())))"
    }
}
