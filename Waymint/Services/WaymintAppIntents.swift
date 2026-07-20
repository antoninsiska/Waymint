import AppIntents
import Foundation

extension Notification.Name {
    static let waymintVoiceAction = Notification.Name("waymintVoiceAction")
}

enum WaymintVoiceAction: String {
    case arrive
    case complete
    case addBreak
}

private enum WaymintVoiceBridge {
    static func queue(_ action: WaymintVoiceAction) {
        UserDefaults.standard.set(action.rawValue, forKey: "waymintPendingVoiceAction")
        NotificationCenter.default.post(name: .waymintVoiceAction, object: action.rawValue)
    }
}

struct WaymintWhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Co následuje ve Waymintu?"
    static var description = IntentDescription("Řekne aktuální nebo následující místo aktivní cesty.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults.standard
        let stop = defaults.string(forKey: "waymintVoiceCurrentStop") ?? "Waymint"
        let detail = defaults.string(forKey: "waymintVoiceCurrentDetail") ?? ""
        return .result(dialog: IntentDialog(stringLiteral: detail.isEmpty ? stop : "\(stop). \(detail)"))
    }
}

struct WaymintArrivedIntent: AppIntent {
    static var title: LocalizedStringResource = "Dorazil jsem ve Waymintu"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WaymintVoiceBridge.queue(.arrive)
        return .result(dialog: "Označím příjezd v aktivní cestě.")
    }
}

struct WaymintCompleteStopIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokončit zastávku ve Waymintu"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WaymintVoiceBridge.queue(.complete)
        return .result(dialog: "Dokončím aktuální zastávku.")
    }
}

struct WaymintAddBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Přidat pauzu ve Waymintu"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WaymintVoiceBridge.queue(.addBreak)
        return .result(dialog: "Přidám deset minut pauzu.")
    }
}

struct WaymintAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WaymintWhatsNextIntent(), phrases: ["Co následuje v \(.applicationName)", "Co je teď v \(.applicationName)"], shortTitle: "Co následuje", systemImageName: "sparkles")
        AppShortcut(intent: WaymintArrivedIntent(), phrases: ["Dorazil jsem v \(.applicationName)"], shortTitle: "Dorazil jsem", systemImageName: "mappin.circle.fill")
        AppShortcut(intent: WaymintCompleteStopIntent(), phrases: ["Hotovo v \(.applicationName)"], shortTitle: "Hotovo", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: WaymintAddBreakIntent(), phrases: ["Přidej pauzu v \(.applicationName)"], shortTitle: "Přidat pauzu", systemImageName: "cup.and.heat.waves")
    }
}
