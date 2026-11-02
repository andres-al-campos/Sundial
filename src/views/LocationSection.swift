import SwiftUI

/// Where the sun is worked out for, confirmed by looking at it: a dot on a map and
/// the times that follow from it. Click or drag to correct it. Not Location
/// Services, because a sunset needs a rough place and nobody has to give up a
/// precise one for it.
struct LocationSection: View {
    @EnvironmentObject var appState: AppState
    /// Where a drag is, so the map follows it and everything else waits for the drop.
    @State private var dragged: RoomLight.Place?

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
            Text("The sunrise and sunset everything follows are worked out for this spot. Roughly is enough, and it stays on this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            map
            // A set height, so the section holds still as the button comes and goes.
            HStack {
                Text(readout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if isPicked, dragged == nil {
                    Button("Use My Time Zone") { pick(nil) }
                        .controlSize(.small)
                }
            }
            .frame(height: 22)
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
        appState.place = place
        appState.save()
        appState.onLampsChanged?()
    }

    private var readout: String {
        guard let shown else { return "Click your part of the world." }
        let lat = "\(abs(Int(shown.latitude.rounded())))° \(shown.latitude < 0 ? "S" : "N")"
        let lon = "\(abs(Int(shown.longitude.rounded())))° \(shown.longitude < 0 ? "W" : "E")"
        guard dragged == nil, let sun = SunClock.sun() else { return "\(lat), \(lon)" }
        return "\(lat), \(lon) · Today: sunrise \(LightsView.time(Int(sun.sunrise.rounded()))), sunset \(LightsView.time(Int(sun.sunset.rounded())))"
    }
}
