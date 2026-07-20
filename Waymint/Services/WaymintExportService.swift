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
        decoder.dateDecodingStrategy = .waymintISO8601
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

    func exportDiagnostics(cities: [CityPlan]) throws -> URL {
        let trips = cities.flatMap(\.sortedTripPlans)
        let payload = WaymintDiagnosticsExport(trips: trips)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Waymint-diagnostika-\(Date().waymintBackupStamp).json")
        try encoder.encode(payload).write(to: url, options: .atomic)
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
        decoder.dateDecodingStrategy = .waymintISO8601
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

private struct WaymintDiagnosticsExport: Encodable {
    struct Trip: Encodable {
        struct Stop: Encodable {
            let number: Int
            let status: String
            let plannedArrival: Date
            let plannedDeparture: Date
            let actualStart: Date?
            let actualEnd: Date?
            let hasCoordinate: Bool
            let isTimeAnchor: Bool
        }
        let number: Int
        let status: String
        let fixedStart: Bool
        let actualStartedAt: Date?
        let actualEndedAt: Date?
        let pauseSeconds: Double
        let stops: [Stop]
        let travelDurations: [Int]
        let eventHistory: [String]
    }

    let format = "waymint.diagnostics"
    let version = 1
    let exportedAt = Date()
    let trips: [Trip]

    init(trips source: [TripPlan]) {
        trips = source.enumerated().map { tripIndex, trip in
            let replacements = Dictionary(uniqueKeysWithValues: trip.sortedStops.enumerated().map { ($0.element.title, "Stop \($0.offset + 1)") })
            let history = trip.scheduleChangeHistoryText.components(separatedBy: .newlines).map { line in
                replacements.reduce(line) { text, value in text.replacingOccurrences(of: value.key, with: value.value) }
            }
            return Trip(
                number: tripIndex + 1,
                status: trip.status.rawValue,
                fixedStart: trip.hasFixedStartTime,
                actualStartedAt: trip.actualStartedAt,
                actualEndedAt: trip.actualEndedAt,
                pauseSeconds: trip.accumulatedPauseSeconds,
                stops: trip.sortedStops.enumerated().map { index, stop in
                    .init(number: index + 1, status: stop.status.rawValue, plannedArrival: stop.plannedArrival, plannedDeparture: stop.plannedDeparture, actualStart: stop.actualStart, actualEnd: stop.actualEnd, hasCoordinate: stop.coordinateIsValid, isTimeAnchor: stop.isTimeAnchor)
                },
                travelDurations: trip.sortedTravelSegments.map(\.plannedDurationMinutes),
                eventHistory: history
            )
        }
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
        self.version = 2
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
    let places: [WaymintExportPlace]

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
        self.places = city.sortedBankPlaces.map(WaymintExportPlace.init)
    }
}

private struct WaymintExportPlace: Encodable {
    let id: UUID
    let title: String
    let type: String
    let highlights: String
    let mainReason: String
    let note: String
    let recommendedVisitDurationMinutes: Int
    let address: String
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    let updatedAt: Date

    init(_ place: PlaceBankItem) {
        id = place.id
        title = place.title
        type = place.stopType.rawValue
        highlights = place.highlights
        mainReason = place.mainReason
        note = place.note
        recommendedVisitDurationMinutes = place.recommendedVisitDurationMinutes
        address = place.address
        latitude = place.latitude
        longitude = place.longitude
        createdAt = place.createdAt
        updatedAt = place.updatedAt
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
    let pausedAt: Date?
    let accumulatedPauseSeconds: Double
    let offlinePreparedAt: Date?
    let delayResponseStrategy: String
    let status: String
    let sortIndex: Int
    let timeRangeLabel: String
    let approximateDurationMinutes: Int
    let landingTitle: String
    let landingSubtitle: String
    let photoAlbumTitle: String?
    let note: String
    let scheduleChangeHistoryText: String
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
        self.pausedAt = trip.pausedAt
        self.accumulatedPauseSeconds = trip.accumulatedPauseSeconds
        self.offlinePreparedAt = trip.offlinePreparedAt
        self.delayResponseStrategy = trip.delayResponseStrategy.rawValue
        self.status = trip.status.rawValue
        self.sortIndex = trip.sortIndex
        self.timeRangeLabel = trip.timeRangeLabel
        self.approximateDurationMinutes = trip.approximateDurationMinutes
        self.landingTitle = trip.landingTitle
        self.landingSubtitle = trip.landingSubtitle
        self.photoAlbumTitle = trip.photoAlbumTitle
        self.note = trip.note
        self.scheduleChangeHistoryText = trip.scheduleChangeHistoryText
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
    let sourceBankPlaceID: UUID?
    let isTimeAnchor: Bool
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
        self.sourceBankPlaceID = stop.sourceBankPlaceID
        self.isTimeAnchor = stop.isTimeAnchor
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
    let places: [WaymintImportPlace]?
}

private struct WaymintImportPlace: Decodable {
    let id: UUID?
    let title: String
    let type: String?
    let highlights: String?
    let mainReason: String?
    let note: String?
    let recommendedVisitDurationMinutes: Int?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date?
    let updatedAt: Date?
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
    let pausedAt: Date?
    let accumulatedPauseSeconds: Double?
    let offlinePreparedAt: Date?
    let delayResponseStrategy: String?
    let status: String
    let landingTitle: String
    let landingSubtitle: String
    let photoAlbumTitle: String?
    let note: String
    let scheduleChangeHistoryText: String?
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
    let sourceBankPlaceID: UUID?
    let isTimeAnchor: Bool?
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

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case code
        case localFilePath
        case externalURLString
        case createdAt
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? TicketType.textCode.rawValue
        code = try container.decodeIfPresent(String.self, forKey: .code)
        localFilePath = try container.decodeIfPresent(String.self, forKey: .localFilePath)
        externalURLString = try container.decodeIfPresent(String.self, forKey: .externalURLString)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
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
            startTime: trip.resolvedStartTime,
            hasFixedStartTime: trip.hasFixedStartTime ?? true,
            actualStartedAt: trip.actualStartedAt,
            actualEndedAt: trip.actualEndedAt,
            pausedAt: trip.pausedAt,
            accumulatedPauseSeconds: trip.accumulatedPauseSeconds ?? 0,
            offlinePreparedAt: trip.offlinePreparedAt,
            delayResponseStrategy: DelayResponseStrategy(rawValue: trip.delayResponseStrategy ?? "") ?? .shiftEverything,
            status: TripPlanStatus(rawValue: trip.status) ?? .draft,
            sortIndex: sortIndex,
            landingTitle: trip.landingTitle,
            landingSubtitle: trip.landingSubtitle,
            photoAlbumLocalIdentifier: nil,
            photoAlbumTitle: trip.photoAlbumTitle,
            note: trip.note,
            scheduleChangeHistoryText: trip.scheduleChangeHistoryText ?? ""
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

private extension WaymintImportTrip {
    var resolvedStartTime: Date {
        let calendar = Calendar.current
        guard calendar.component(.year, from: startTime) < 2002 else {
            return startTime
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: startTime)
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        combined.second = timeComponents.second
        return calendar.date(from: combined) ?? date
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

        for importedPlace in city.places ?? [] {
            let place = PlaceBankItem(
                title: importedPlace.title,
                stopType: StopType(rawValue: importedPlace.type ?? "") ?? .custom,
                highlights: importedPlace.highlights ?? "",
                mainReason: importedPlace.mainReason ?? "",
                note: importedPlace.note ?? "",
                recommendedVisitDurationMinutes: importedPlace.recommendedVisitDurationMinutes ?? 45,
                address: importedPlace.address ?? "",
                latitude: importedPlace.latitude,
                longitude: importedPlace.longitude
            )
            place.id = importedPlace.id ?? UUID()
            place.createdAt = importedPlace.createdAt ?? .now
            place.updatedAt = importedPlace.updatedAt ?? .now
            addBankPlace(place)
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
            sortIndex: stop.sortIndex,
            sourceBankPlaceID: stop.sourceBankPlaceID,
            isTimeAnchor: stop.isTimeAnchor ?? false
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

private extension JSONDecoder.DateDecodingStrategy {
    static var waymintISO8601: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }

            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateOnlyFormatter.date(from: value) {
                return date
            }

            let timeOnlyFormatter = DateFormatter()
            timeOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            timeOnlyFormatter.calendar = Calendar(identifier: .gregorian)
            timeOnlyFormatter.defaultDate = Date(timeIntervalSinceReferenceDate: 0)
            timeOnlyFormatter.dateFormat = "HH:mm"
            if let date = timeOnlyFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Neplatne ISO 8601 datum: \(value)"
            )
        }
    }
}
