import SwiftData

enum WaymintModelContainer {
    static var schema: Schema {
        Schema([
            CityPlan.self,
            PlaceBankItem.self,
            TripPlan.self,
            TripStop.self,
            StopChecklistItem.self,
            TravelSegment.self,
            TicketItem.self,
            AttachmentItem.self
        ])
    }

    static func make(inMemory: Bool = false, iCloudSyncEnabled: Bool = ICloudSyncSettings.isEnabled) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if iCloudSyncEnabled && !inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(ICloudSyncSettings.containerIdentifier)
            )
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
