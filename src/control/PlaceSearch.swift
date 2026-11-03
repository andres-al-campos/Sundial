import MapKit

/// Finds a city by name through Apple's place search, for people who couldn't point
/// to theirs on a small map. Only what's typed goes to Apple, and only while typing.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var problem: String?
    private let completer = MKLocalSearchCompleter()
    static let shownResults = 5

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Cities, not street addresses: a sunset doesn't need anyone's house.
        if #available(macOS 15, *) {
            completer.addressFilter = MKAddressFilter(including: [.locality, .subLocality, .administrativeArea])
        }
    }

    func find(_ text: String) {
        problem = nil
        let query = text.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = query
        }
    }

    func coordinate(of result: MKLocalSearchCompletion) async -> (latitude: Double, longitude: Double)? {
        do {
            let found = try await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start()
            if let at = found.mapItems.first?.placemark.coordinate { return (at.latitude, at.longitude) }
        } catch {}
        problem = "Couldn't find where that is. Check your connection and try again, or click your spot on the map."
        return nil
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            guard !completer.queryFragment.isEmpty else { return }
            results = Array(completer.results.prefix(Self.shownResults))
            problem = results.isEmpty ? "No cities match that. Check the spelling, or click your spot on the map." : nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            results = []
            problem = (error as? MKError)?.code == .placemarkNotFound
                ? "No cities match that. Check the spelling, or click your spot on the map."
                : "Couldn't reach Apple's place search. Check your connection, or click your spot on the map."
        }
    }
}
