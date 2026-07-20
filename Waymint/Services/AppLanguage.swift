import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, cs, en
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Podle systému"; case .cs: "Čeština"; case .en: "English" }
    }
    var locale: Locale {
        switch self { case .system: .autoupdatingCurrent; case .cs: Locale(identifier: "cs"); case .en: Locale(identifier: "en") }
    }
}

enum WaymintLocalization {
    private static var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "waymintAppLanguage") ?? "system") ?? .system
    }

    static func text(_ key: String) -> String {
        let selected = selectedLanguage
        guard selected != .system,
              let path = Bundle.main.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: selectedLanguage.locale, arguments: arguments)
    }

    static var currentLocale: Locale { selectedLanguage.locale }

    static func countryName(_ storedValue: String) -> String {
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text("Bez země") }
        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        let regionCodes: [String: String] = [
            "finsko": "FI", "finland": "FI", "suomi": "FI",
            "svedsko": "SE", "sweden": "SE", "sverige": "SE",
            "cesko": "CZ", "czechia": "CZ", "czech republic": "CZ",
            "norsko": "NO", "norway": "NO", "dansko": "DK", "denmark": "DK",
            "estonsko": "EE", "estonia": "EE", "nemecko": "DE", "germany": "DE",
            "rakousko": "AT", "austria": "AT", "italie": "IT", "italy": "IT",
            "spanelsko": "ES", "spain": "ES", "francie": "FR", "france": "FR",
            "polsko": "PL", "poland": "PL", "slovensko": "SK", "slovakia": "SK",
            "velka britanie": "GB", "united kingdom": "GB", "usa": "US", "united states": "US"
        ]
        guard let code = regionCodes[normalized] else { return trimmed }
        return selectedLanguage.locale.localizedString(forRegionCode: code) ?? trimmed
    }
}
