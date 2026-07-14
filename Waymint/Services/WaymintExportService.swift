import Foundation

@MainActor
struct WaymintExportService {
    enum ImportError: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Soubor není platný export Waymint."
            }
        }
    }

    func exportLibrary(cities: [CityPlan]) throws -> URL {
        let envelope = WaymintLibraryFileExport(cities: cities)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        let filename = "Waymint-zaloha-\(Date().waymintBackupStamp).waymint"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func importLibrary(from url: URL, nextSortIndex: Int) throws -> [CityPlan] {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try normalizedJSONData(from: url)
        return try importLibrary(fromData: data, nextSortIndex: nextSortIndex)
    }

    func importLibrary(fromText text: String, nextSortIndex: Int) throws -> [CityPlan] {
        try importLibrary(fromData: normalizedJSONData(fromText: text), nextSortIndex: nextSortIndex)
    }

    private func importLibrary(fromData data: Data, nextSortIndex: Int) throws -> [CityPlan] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(WaymintLibraryFileImport.self, from: data)
        guard envelope.format == "waymint.library" else {
            throw ImportError.unsupportedFormat
        }
        return envelope.cities
            .sorted { $0.sortIndex < $1.sortIndex }
            .enumerated()
            .map { offset, city in
                CityPlan(imported: city, sortIndex: nextSortIndex + offset)
            }
    }

    func exportTrip(_ trip: TripPlan) throws -> URL {
        let envelope = WaymintTripFileExport(trip: trip)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        let filename = "Waymint-\(trip.title.filenameSafe).way"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func importTrip(from url: URL, nextSortIndex: Int) throws -> TripPlan {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try normalizedJSONData(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(WaymintTripFileImport.self, from: data)
        guard envelope.format == "waymint.trip" else {
            throw ImportError.unsupportedFormat
        }
        return TripPlan(imported: envelope.trip, sortIndex: nextSortIndex)
    }

    private func normalizedJSONData(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }

        return normalizedJSONData(fromText: text)
    }

    private func normalizedJSONData(fromText rawText: String) -> Data {
        var text = rawText
        text = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "„", with: "\"")
            .replacingOccurrences(of: "‟", with: "\"")

        return Data(text.utf8)
    }
}

private struct WaymintLibraryFileExport: Encodable {
    let format: String
    let version: Int
    let exportedAt: Date
    let brand: WaymintExportBrand
    let cities: [WaymintExportCity]

    init(cities: [CityPlan]) {
        self.format = "waymint.library"
        self.version = 1
        self.exportedAt = .now
        self.brand = WaymintExportBrand()
        self.cities = cities
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(WaymintExportCity.init)
    }
}

private struct WaymintExportCity: Encodable {
    let id: UUID
    let name: String
    let country: String
    let landingTitle: String
    let landingSubtitle: String
    let sortIndex: Int
    let createdAt: Date
    let updatedAt: Date
    let trips: [WaymintExportTrip]

    init(_ city: CityPlan) {
        self.id = city.id
        self.name = city.name
        self.country = city.country
        self.landingTitle = city.landingTitle
        self.landingSubtitle = city.landingSubtitle
        self.sortIndex = city.sortIndex
        self.createdAt = city.createdAt
        self.updatedAt = city.updatedAt
        self.trips = city.sortedTripPlans.map(WaymintExportTrip.init)
    }
}

private struct WaymintTripFileExport: Encodable {
    let format: String
    let version: Int
    let exportedAt: Date
    let brand: WaymintExportBrand
    let trip: WaymintExportTrip

    init(trip: TripPlan) {
        self.format = "waymint.trip"
        self.version = 1
        self.exportedAt = .now
        self.brand = WaymintExportBrand()
        self.trip = WaymintExportTrip(trip)
    }
}

private struct WaymintExportBrand: Encodable {
    let appName = "Waymint"
    let logoText = "WM"
    let fileExtension = ".way"
    let primaryColorHex = "#247A53"
    let darkRouteColorHex = "#0A281C"
    let description = "Waymint route export. The file is JSON with a custom .way extension."
}

private struct WaymintExportTrip: Encodable {
    let id: UUID
    let cityName: String?
    let country: String?
    let title: String
    let date: Date
    let startTime: Date
    let hasFixedStartTime: Bool
    let actualStartedAt: Date?
    let actualEndedAt: Date?
    let status: String
    let sortIndex: Int
    let timeRangeLabel: String
    let approximateDurationMinutes: Int
    let landingTitle: String
    let landingSubtitle: String
    let photoAlbumTitle: String?
    let note: String
    let stops: [WaymintExportStop]
    let travelSegments: [WaymintExportTravelSegment]
    let tickets: [WaymintExportTicket]

    init(_ trip: TripPlan) {
        self.id = trip.id
        self.cityName = trip.city?.name
        self.country = trip.city?.country
        self.title = trip.title
        self.date = trip.date
        self.startTime = trip.startTime
        self.hasFixedStartTime = trip.hasFixedStartTime
        self.actualStartedAt = trip.actualStartedAt
        self.actualEndedAt = trip.actualEndedAt
        self.status = trip.status.rawValue
        self.sortIndex = trip.sortIndex
        self.timeRangeLabel = trip.timeRangeLabel
        self.approximateDurationMinutes = trip.approximateDurationMinutes
        self.landingTitle = trip.landingTitle
        self.landingSubtitle = trip.landingSubtitle
        self.photoAlbumTitle = trip.photoAlbumTitle
        self.note = trip.note
        self.stops = trip.sortedStops.map(WaymintExportStop.init)
        self.travelSegments = trip.sortedTravelSegments.map(WaymintExportTravelSegment.init)
        self.tickets = trip.sortedTickets.map(WaymintExportTicket.init)
    }
}

private struct WaymintExportStop: Encodable {
    let id: UUID
    let title: String
    let type: String
    let status: String
    let plannedArrival: Date
    let plannedDeparture: Date
    let plannedVisitDurationMinutes: Int
    let address: String
    let latitude: Double?
    let longitude: Double?
    let note: String
    let mainReason: String
    let isRequired: Bool
    let sortIndex: Int
    let checklist: [WaymintExportChecklistItem]
    let tickets: [WaymintExportTicket]

    init(_ stop: TripStop) {
        self.id = stop.id
        self.title = stop.title
        self.type = stop.stopType.rawValue
        self.status = stop.status.rawValue
        self.plannedArrival = stop.plannedArrival
        self.plannedDeparture = stop.plannedDeparture
        self.plannedVisitDurationMinutes = stop.plannedVisitDurationMinutes
        self.address = stop.address
        self.latitude = stop.latitude
        self.longitude = stop.longitude
        self.note = stop.note
        self.mainReason = stop.mainReason
        self.isRequired = stop.isRequired
        self.sortIndex = stop.sortIndex
        self.checklist = stop.sortedChecklistItems.map(WaymintExportChecklistItem.init)
        self.tickets = stop.sortedTickets.map(WaymintExportTicket.init)
    }
}

private struct WaymintExportTravelSegment: Encodable {
    let id: UUID
    let transportMode: String
    let plannedDurationMinutes: Int
    let plannedDeparture: Date?
    let bufferMinutes: Int
    let fromStopID: UUID?
    let toStopID: UUID?
    let note: String
    let sortIndex: Int

    init(_ segment: TravelSegment) {
        self.id = segment.id
        self.transportMode = segment.transportMode.rawValue
        self.plannedDurationMinutes = segment.plannedDurationMinutes
        self.plannedDeparture = segment.plannedDeparture
        self.bufferMinutes = segment.bufferMinutes
        self.fromStopID = segment.fromStopID
        self.toStopID = segment.toStopID
        self.note = segment.note
        self.sortIndex = segment.sortIndex
    }
}

private struct WaymintExportTicket: Encodable {
    let id: UUID
    let title: String
    let type: String
    let code: String?
    let localFilePath: String?
    let externalURLString: String?
    let createdAt: Date
    let note: String

    init(_ ticket: TicketItem) {
        self.id = ticket.id
        self.title = ticket.title
        self.type = ticket.ticketType.rawValue
        self.code = ticket.code
        self.localFilePath = ticket.localFilePath
        self.externalURLString = ticket.externalURLString
        self.createdAt = ticket.createdAt
        self.note = ticket.note
    }
}

private struct WaymintExportChecklistItem: Encodable {
    let id: UUID
    let title: String
    let isDone: Bool
    let sortIndex: Int

    init(_ item: StopChecklistItem) {
        self.id = item.id
        self.title = item.title
        self.isDone = item.isDone
        self.sortIndex = item.sortIndex
    }
}

private struct WaymintTripFileImport: Decodable {
    let format: String
    let version: Int
    let trip: WaymintImportTrip
}

private struct WaymintLibraryFileImport: Decodable {
    let format: String
    let version: Int
    let cities: [WaymintImportCity]
}

private struct WaymintImportCity: Decodable {
    let id: UUID?
    let name: String
    let country: String
    let landingTitle: String?
    let landingSubtitle: String?
    let sortIndex: Int
    let createdAt: Date?
    let updatedAt: Date?
    let trips: [WaymintImportTrip]
}

private struct WaymintImportTrip: Decodable {
    let id: UUID?
    let cityName: String?
    let country: String?
    let title: String
    let date: Date
    let startTime: Date
    let hasFixedStartTime: Bool?
    let actualStartedAt: Date?
    let actualEndedAt: Date?
    let status: String
    let landingTitle: String
    let landingSubtitle: String
    let photoAlbumTitle: String?
    let note: String
    let stops: [WaymintImportStop]
    let travelSegments: [WaymintImportTravelSegment]
    let tickets: [WaymintImportTicket]
}

private struct WaymintImportStop: Decodable {
    let id: UUID
    let title: String
    let type: String
    let status: String
    let plannedArrival: Date
    let plannedDeparture: Date
    let plannedVisitDurationMinutes: Int
    let address: String
    let latitude: Double?
    let longitude: Double?
    let note: String
    let mainReason: String
    let isRequired: Bool
    let sortIndex: Int
    let checklist: [WaymintImportChecklistItem]
    let tickets: [WaymintImportTicket]
}

private struct WaymintImportTravelSegment: Decodable {
    let id: UUID?
    let transportMode: String
    let plannedDurationMinutes: Int
    let plannedDeparture: Date?
    let bufferMinutes: Int
    let fromStopID: UUID?
    let toStopID: UUID?
    let note: String
    let sortIndex: Int
}

private struct WaymintImportTicket: Decodable {
    let id: UUID?
    let title: String
    let type: String
    let code: String?
    let localFilePath: String?
    let externalURLString: String?
    let createdAt: Date
    let note: String
}

private struct WaymintImportChecklistItem: Decodable {
    let id: UUID?
    let title: String
    let isDone: Bool
    let sortIndex: Int
}

private extension TripPlan {
    convenience init(imported trip: WaymintImportTrip, sortIndex: Int) {
        self.init(
            id: trip.id ?? UUID(),
            title: trip.title,
            date: trip.date,
            startTime: trip.startTime,
            hasFixedStartTime: trip.hasFixedStartTime ?? true,
            actualStartedAt: trip.actualStartedAt,
            actualEndedAt: trip.actualEndedAt,
            status: TripPlanStatus(rawValue: trip.status) ?? .draft,
            sortIndex: sortIndex,
            landingTitle: trip.landingTitle,
            landingSubtitle: trip.landingSubtitle,
            photoAlbumLocalIdentifier: nil,
            photoAlbumTitle: trip.photoAlbumTitle,
            note: trip.note
        )

        var stopIDMap: [UUID: UUID] = [:]
        for importedStop in trip.stops.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let stop = TripStop(imported: importedStop)
            stopIDMap[importedStop.id] = stop.id
            addStop(stop)
        }

        for importedSegment in trip.travelSegments.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let segment = TravelSegment(
                id: importedSegment.id ?? UUID(),
                transportMode: TransportMode(rawValue: importedSegment.transportMode) ?? .walking,
                plannedDurationMinutes: importedSegment.plannedDurationMinutes,
                plannedDeparture: importedSegment.plannedDeparture,
                bufferMinutes: importedSegment.bufferMinutes,
                fromStopID: importedSegment.fromStopID.flatMap { stopIDMap[$0] },
                toStopID: importedSegment.toStopID.flatMap { stopIDMap[$0] },
                note: importedSegment.note,
                sortIndex: importedSegment.sortIndex
            )
            addTravelSegment(segment)
        }

        for importedTicket in trip.tickets {
            addTicket(TicketItem(imported: importedTicket))
        }
    }
}

private extension CityPlan {
    convenience init(imported city: WaymintImportCity, sortIndex: Int) {
        self.init(
            id: city.id ?? UUID(),
            name: city.name,
            country: city.country,
            landingTitle: city.landingTitle ?? "",
            landingSubtitle: city.landingSubtitle ?? "",
            sortIndex: sortIndex,
            createdAt: city.createdAt ?? .now,
            updatedAt: city.updatedAt ?? .now
        )

        for (index, importedTrip) in city.trips.sorted(by: { $0.date < $1.date }).enumerated() {
            addTripPlan(TripPlan(imported: importedTrip, sortIndex: index))
        }
    }
}

private extension TripStop {
    convenience init(imported stop: WaymintImportStop) {
        self.init(
            id: stop.id,
            title: stop.title,
            stopType: StopType(rawValue: stop.type) ?? .custom,
            status: StopStatus(rawValue: stop.status) ?? .planned,
            plannedArrival: stop.plannedArrival,
            plannedDeparture: stop.plannedDeparture,
            plannedVisitDurationMinutes: stop.plannedVisitDurationMinutes,
            address: stop.address,
            latitude: stop.latitude,
            longitude: stop.longitude,
            note: stop.note,
            mainReason: stop.mainReason,
            isRequired: stop.isRequired,
            sortIndex: stop.sortIndex
        )

        for importedChecklistItem in stop.checklist.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            addChecklistItem(StopChecklistItem(imported: importedChecklistItem))
        }

        for importedTicket in stop.tickets {
            addTicket(TicketItem(imported: importedTicket))
        }
    }
}

private extension TicketItem {
    convenience init(imported ticket: WaymintImportTicket) {
        self.init(
            id: ticket.id ?? UUID(),
            title: ticket.title,
            ticketType: TicketType(rawValue: ticket.type) ?? .textCode,
            code: ticket.code,
            localFilePath: ticket.localFilePath,
            externalURLString: ticket.externalURLString,
            createdAt: ticket.createdAt,
            note: ticket.note
        )
    }
}

private extension StopChecklistItem {
    convenience init(imported item: WaymintImportChecklistItem) {
        self.init(
            id: item.id ?? UUID(),
            title: item.title,
            isDone: item.isDone,
            sortIndex: item.sortIndex
        )
    }
}

private extension String {
    var filenameSafe: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let cleaned = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return cleaned.isEmpty ? "City" : cleaned
    }
}

private extension Date {
    var waymintBackupStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: self)
    }
}
