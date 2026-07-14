import Foundation

enum ICloudSyncSettings {
    static let enabledKey = "waymintICloudSyncEnabled"
    static let userConsentKey = "waymintICloudSyncConsentAccepted"
    static let containerIdentifier = "iCloud.com.example.Waymint"
    static let isAvailableInCurrentBuild = false

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        return isAvailableInCurrentBuild && defaults.bool(forKey: enabledKey) && defaults.bool(forKey: userConsentKey)
    }
}
