import Foundation
import MapKit

@MainActor
final class RouteCacheService {
    static let shared = RouteCacheService()

    struct Entry: Codable {
        struct Point: Codable {
            let latitude: Double
            let longitude: Double
        }
        let points: [Point]
        let isEstimated: Bool
        let savedAt: Date

        var polyline: MKPolyline {
            var coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            return MKPolyline(coordinates: &coordinates, count: coordinates.count)
        }
    }

    private var entries: [String: Entry] = [:]
    private let fileURL: URL
    private var writeGeneration = 0

    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileURL = directory.appendingPathComponent("waymint-route-cache.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    func entry(for key: String) -> Entry? {
        guard let entry = entries[key] else { return nil }
        let maximumAge: TimeInterval = entry.isEstimated ? 15 * 60 : 30 * 24 * 60 * 60
        guard Date().timeIntervalSince(entry.savedAt) <= maximumAge else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry
    }

    func store(polyline: MKPolyline, isEstimated: Bool, for key: String) {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        entries[key] = Entry(
            points: coordinates.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
            isEstimated: isEstimated,
            savedAt: .now
        )
        if entries.count > 500 {
            let newest = entries.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(400)
            entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let destination = fileURL
        writeGeneration += 1
        let generation = writeGeneration
        Task(priority: .utility) {
            await RouteCacheWriter.shared.write(data, to: destination, generation: generation)
        }
    }
}

private actor RouteCacheWriter {
    static let shared = RouteCacheWriter()
    private var latestGeneration = 0

    func write(_ data: Data, to url: URL, generation: Int) {
        guard generation > latestGeneration else { return }
        latestGeneration = generation
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
struct TripOfflinePreparationResult {
    let routeCount: Int
    let estimatedRouteCount: Int
    let missingTicketFiles: Int
}

@MainActor
enum TripOfflinePreparationService {
    static func prepare(_ trip: TripPlan) async -> TripOfflinePreparationResult {
        let lines = await TripMapRouteBuilder.routeLines(for: trip)
        let missingFiles = trip.allTickets.filter { ticket in
            guard let path = ticket.localFilePath, !path.isEmpty else { return false }
            return !FileManager.default.fileExists(atPath: path)
        }.count
        trip.offlinePreparedAt = .now
        trip.updatedAt = .now
        return .init(
            routeCount: lines.count,
            estimatedRouteCount: lines.filter(\.isEstimated).count,
            missingTicketFiles: missingFiles
        )
    }
}
