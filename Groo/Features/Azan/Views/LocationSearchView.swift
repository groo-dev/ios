//
//  LocationSearchView.swift
//  Groo
//
//  Location search using Apple MapKit's MKLocalSearchCompleter.
//  No API key needed.
//

import MapKit
import SwiftUI

struct LocationSearchView: View {
    let onSelect: (Double, Double, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchCompleter = LocationSearchCompleter()

    var body: some View {
        List {
            if searchCompleter.results.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }

            ForEach(searchCompleter.results) { result in
                Button {
                    selectResult(result)
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(result.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search city or address")
        .onChange(of: searchText) { _, query in
            searchCompleter.search(query: query)
        }
        .navigationTitle("Search Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func selectResult(_ result: LocationResult) {
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = [result.title, result.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                if let item = response.mapItems.first {
                    let coord = item.placemark.coordinate
                    let name = buildLocationName(from: item.placemark)
                    onSelect(coord.latitude, coord.longitude, name)
                    dismiss()
                }
            } catch {
                print("[LocationSearch] Search failed: \(error)")
            }
        }
    }

    private func buildLocationName(from placemark: MKPlacemark) -> String {
        let city = placemark.locality ?? ""
        let country = placemark.country ?? ""
        if !city.isEmpty && !country.isEmpty {
            return "\(city), \(country)"
        }
        return city.isEmpty ? country : city
    }
}

// MARK: - Search Result Model

struct LocationResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

// MARK: - Search Completer

@MainActor
@Observable
class LocationSearchCompleter: NSObject {
    var results: [LocationResult] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }
}

extension LocationSearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map {
            LocationResult(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in
            self.results = mapped
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("[LocationSearch] Completer error: \(error)")
    }
}
