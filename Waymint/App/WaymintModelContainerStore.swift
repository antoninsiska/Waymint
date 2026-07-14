import Combine
import SwiftData
import SwiftUI

@MainActor
final class WaymintModelContainerStore: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var containerID = UUID()
    @Published private(set) var isUsingICloudSync: Bool

    init() {
        let iCloudSyncEnabled = ICloudSyncSettings.isEnabled
        self.isUsingICloudSync = iCloudSyncEnabled
        do {
            self.container = try WaymintModelContainer.make(iCloudSyncEnabled: iCloudSyncEnabled)
        } catch {
            self.isUsingICloudSync = false
            do {
                self.container = try WaymintModelContainer.make(iCloudSyncEnabled: false)
            } catch {
                fatalError("SwiftData container could not be created: \(error)")
            }
        }
    }

    func reloadForCurrentSettings() {
        let iCloudSyncEnabled = ICloudSyncSettings.isEnabled
        guard iCloudSyncEnabled != isUsingICloudSync else { return }
        do {
            container = try WaymintModelContainer.make(iCloudSyncEnabled: iCloudSyncEnabled)
            isUsingICloudSync = iCloudSyncEnabled
            containerID = UUID()
        } catch {
            UserDefaults.standard.set(false, forKey: ICloudSyncSettings.enabledKey)
            isUsingICloudSync = false
        }
    }
}
