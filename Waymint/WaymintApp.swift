import SwiftData
import SwiftUI
import UIKit
import UserNotifications

final class WaymintAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@main
struct WaymintApp: App {
    @UIApplicationDelegateAdaptor(WaymintAppDelegate.self) private var appDelegate

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
    @AppStorage("waymintAppLanguage") private var appLanguageRaw = AppLanguage.system.rawValue

    var body: some View {
        ContentView()
            .environment(\.locale, (AppLanguage(rawValue: appLanguageRaw) ?? .system).locale)
            .id("\(modelContainerStore.containerID.uuidString)-\(appLanguageRaw)")
            .modelContainer(modelContainerStore.container)
            .task {
                let cleanupKey = "waymintNotificationCleanupV2"
                guard !UserDefaults.standard.bool(forKey: cleanupKey) else { return }
                NotificationScheduler().cancelAllNotifications()
                UserDefaults.standard.set(true, forKey: cleanupKey)
            }
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
