import SwiftData
import SwiftUI

@main
struct WaymintApp: App {
    var body: some Scene {
        WindowGroup {
            WaymintRootContainerView()
        }
    }
}

private struct WaymintRootContainerView: View {
    @AppStorage(ICloudSyncSettings.enabledKey) private var iCloudSyncEnabled = false
    @AppStorage(ICloudSyncSettings.userConsentKey) private var iCloudSyncConsentAccepted = false
    @StateObject private var modelContainerStore = WaymintModelContainerStore()

    var body: some View {
        ContentView()
            .id(modelContainerStore.containerID)
            .modelContainer(modelContainerStore.container)
            .onChange(of: iCloudSyncEnabled) { _, _ in
                modelContainerStore.reloadForCurrentSettings()
            }
            .onChange(of: iCloudSyncConsentAccepted) { _, _ in
                modelContainerStore.reloadForCurrentSettings()
            }
            .onChange(of: modelContainerStore.isUsingICloudSync) { _, isUsingICloudSync in
                UserDefaults.standard.set(isUsingICloudSync, forKey: ICloudSyncSettings.enabledKey)
            }
        }
}
