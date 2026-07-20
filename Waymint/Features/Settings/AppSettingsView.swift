import CoreLocation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct AppSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CityPlan.sortIndex) private var cities: [CityPlan]
    @AppStorage("waymintNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage(ICloudSyncSettings.enabledKey) private var iCloudSyncEnabled = false
    @AppStorage(ICloudSyncSettings.userConsentKey) private var iCloudSyncConsentAccepted = false
    @AppStorage("waymintHasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("activeTripShowCurrentStop") private var showCurrentStop = true
    @AppStorage("activeTripShowNextStop") private var showNextStop = false
    @AppStorage("activeTripShowDepartureTime") private var showDepartureTime = true
    @AppStorage("activeTripShowDelay") private var showDelay = true
    @AppStorage("waymintLiveActivityPreset") private var liveActivityPreset = "departure"
    @AppStorage("waymintPlaceBankEnabled") private var placeBankEnabled = false
    @AppStorage("waymintGPSArrivalRadius") private var gpsArrivalRadius = 85
    @AppStorage("waymintGPSDepartureRadius") private var gpsDepartureRadius = 140
    @AppStorage("waymintGPSDepartureConfirmationSeconds") private var gpsDepartureConfirmationSeconds = 20
    @AppStorage("waymintAppLanguage") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage("waymintEmergencyPowerMode") private var emergencyPowerMode = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingICloudConsent = false
    @State private var exportedLibraryFile: ExportedWayFile?
    @State private var exportedDiagnosticsFile: ExportedWayFile?
    @State private var importingLibrary = false
    @State private var showingTextImport = false
    @State private var syncErrorMessage = ""
    @State private var showingSyncError = false
    @State private var showingImportDone = false
    @State private var showingDataHealth = false
    @State private var locationAuthorizationStatus = CLLocationManager().authorizationStatus
    @State private var notificationAuthorizationStatus = UNAuthorizationStatus.notDetermined
    @State private var notificationMessage: String?
    private let exportService = WaymintExportService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Režimy aplikace") {
                    Toggle("Banka míst", isOn: $placeBankEnabled)
                    Text("Přidá katalog míst rozdělený podle měst. Při tvorbě zastávky pak můžeš převzít uložené údaje a řešit hlavně přesun.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("Jazyk") {
                    Picker("Jazyk aplikace", selection: $appLanguageRaw) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.title)).tag(language.rawValue)
                        }
                    }
                }

                Section("Ruční synchronizace") {
                    Button {
                        exportLibrary()
                    } label: {
                        Label("Exportovat všechna data", systemImage: "square.and.arrow.up")
                    }
                    .disabled(cities.isEmpty)

                    Button {
                        importingLibrary = true
                    } label: {
                        Label("Nahrát zálohu a synchronizovat", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        showingTextImport = true
                    } label: {
                        Label("Vložit AI text ze schránky", systemImage: "text.badge.plus")
                    }

                    Text("Export vytvoří jeden soubor se všemi městy, cestami, zastávkami, checklisty a metadaty vstupenek. Můžeš ho nahrát jako soubor, nebo vložit čistý JSON text od AI.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("iCloud") {
                    Toggle("Synchronizovat přes iCloud", isOn: iCloudSyncBinding)
                        .disabled(!ICloudSyncSettings.isAvailableInCurrentBuild)

                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(LocalizedStringKey(iCloudStatusTitle))
                        } icon: {
                            Image(systemName: iCloudStatusIcon)
                        }
                            .font(.subheadline.weight(.semibold))
                        Text(LocalizedStringKey(iCloudStatusMessage))
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }

                Section("Upozornění") {
                    Toggle("Upozornit na odchod a příjezd", isOn: $notificationsEnabled)
                    HStack {
                        Label("Stav oznámení", systemImage: notificationStatusIcon)
                        Spacer()
                        Text(notificationStatusTitle)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    Button {
                        testNotifications()
                    } label: {
                        Label("Poslat test za 5 sekund", systemImage: "bell.badge")
                    }
                    .disabled(notificationAuthorizationStatus == .denied)
                    if notificationAuthorizationStatus == .denied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Otevřít nastavení oznámení", systemImage: "gear")
                        }
                    }
                    Text("Waymint může připomenout čas odchodu, správný čas u místa a vstupenky poblíž zastávky.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("GPS automatika") {
                    HStack {
                        Label("Přístup k poloze", systemImage: "location.fill")
                        Spacer()
                        Text(locationAuthorizationTitle)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Otevřít nastavení polohy", systemImage: "gear")
                    }
                    DisclosureGroup("Pokročilé nastavení GPS") {
                        Stepper(WaymintLocalization.format("Příchod do %d m", gpsArrivalRadius), value: $gpsArrivalRadius, in: 30...150, step: 5)
                        Stepper(WaymintLocalization.format("Odchod od %d m", gpsDepartureRadius), value: $gpsDepartureRadius, in: 80...300, step: 10)
                        Stepper(WaymintLocalization.format("Potvrdit odchod po %d s", gpsDepartureConfirmationSeconds), value: $gpsDepartureConfirmationSeconds, in: 10...60, step: 5)
                        Text("Větší rozdíl mezi příchodem a odchodem omezuje falešné přepnutí při nepřesné GPS.")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }

                Section("Baterie") {
                    Toggle("Nouzový úsporný režim", isOn: $emergencyPowerMode)
                    Text("Při zapnutém režimu nízké spotřeby Waymint sníží přesnost a četnost GPS aktualizací. Automatické přepnutí zastávky zůstane konzervativní.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("Lock Screen a Dynamic Island") {
                    Picker("Hlavní údaj", selection: $liveActivityPreset) {
                        Text("Příští odchod").tag("departure")
                        Text("Čas na místě").tag("remaining")
                        Text("Navigace k cíli").tag("navigation")
                        Text("Celkové zpoždění").tag("delay")
                    }
                    DisclosureGroup("Vlastní zobrazení") {
                        Toggle("Aktuální zastávka", isOn: $showCurrentStop)
                        Toggle("Další zastávka", isOn: $showNextStop)
                        Toggle("Čas odchodu", isOn: $showDepartureTime)
                        Toggle("Zpoždění", isOn: $showDelay)
                    }
                }

                Section("Vzhled") {
                    Label("Waymint používá systémový světlý nebo tmavý režim.", systemImage: "circle.lefthalf.filled")
                }

                Section("Nápověda") {
                    Button { showingDataHealth = true } label: {
                        Label("Zkontrolovat data", systemImage: "checkmark.shield")
                    }
                    Button {
                        hasSeenOnboarding = false
                        dismiss()
                    } label: {
                        Label("Zobrazit průvodce znovu", systemImage: "questionmark.circle")
                    }
                    Button {
                        exportDiagnostics()
                    } label: {
                        Label("Exportovat anonymní diagnostiku", systemImage: "stethoscope")
                    }
                }
            }
            .navigationTitle("Nastavení")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .alert("Zapnout iCloud synchronizaci?", isPresented: $showingICloudConsent) {
                Button("Zrušit", role: .cancel) {
                    iCloudSyncEnabled = false
                }
                Button("Souhlasím") {
                    iCloudSyncConsentAccepted = true
                    iCloudSyncEnabled = true
                }
            } message: {
                Text("Waymint uloží data do tvého soukromého iCloud kontejneru, aby se mohla synchronizovat mezi iPhonem a iPadem přihlášenými ke stejnému Apple ID. Přiložené lokální soubory vstupenek mohou zůstat jen na zařízení.")
            }
            .alert("Synchronizace se nepovedla", isPresented: $showingSyncError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncErrorMessage)
            }
            .alert("Záloha je nahraná", isPresented: $showingImportDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Data ze souboru byla přidaná do Waymint.")
            }
            .alert("Oznámení", isPresented: Binding(get: { notificationMessage != nil }, set: { if !$0 { notificationMessage = nil } })) {
                Button("OK", role: .cancel) { notificationMessage = nil }
            } message: {
                Text(notificationMessage ?? "")
            }
            .sheet(item: $exportedLibraryFile) { file in
                ShareSheet(activityItems: [
                    WaymintFileActivityItem(url: file.url, title: "Waymint záloha")
                ])
            }
            .sheet(item: $exportedDiagnosticsFile) { file in
                ShareSheet(activityItems: [file.url])
            }
            .sheet(isPresented: $showingTextImport) {
                WaymintTextImportView { text in
                    importLibrary(fromText: text)
                }
            }
            .sheet(isPresented: $showingDataHealth) { DataHealthView() }
            .fileImporter(
                isPresented: $importingLibrary,
                allowedContentTypes: [.waymintLibrary, .json],
                allowsMultipleSelection: false,
                onCompletion: importLibrary
            )
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            if !enabled {
                NotificationScheduler().cancelAllNotifications()
            } else {
                Task {
                    let allowed = (try? await NotificationScheduler().requestPermissionIfNeeded()) == true
                    await refreshNotificationStatus()
                    if !allowed {
                        notificationsEnabled = false
                        notificationMessage = WaymintLocalization.text("Oznámení jsou v systému vypnutá. Povol je prosím v Nastavení.")
                    }
                }
            }
        }
        .onChange(of: liveActivityPreset) { _, preset in
            switch preset {
            case "remaining":
                showCurrentStop = true; showNextStop = false; showDepartureTime = true; showDelay = false
            case "navigation":
                showCurrentStop = true; showNextStop = true; showDepartureTime = false; showDelay = false
            case "delay":
                showCurrentStop = true; showNextStop = false; showDepartureTime = false; showDelay = true
            default:
                showCurrentStop = true; showNextStop = true; showDepartureTime = true; showDelay = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                locationAuthorizationStatus = CLLocationManager().authorizationStatus
                Task { await refreshNotificationStatus() }
            }
        }
        .task {
            await refreshNotificationStatus()
        }
    }

    private func exportLibrary() {
        do {
            exportedLibraryFile = ExportedWayFile(url: try exportService.exportLibrary(cities: cities))
        } catch {
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
        }
    }

    private func exportDiagnostics() {
        do {
            exportedDiagnosticsFile = ExportedWayFile(url: try exportService.exportDiagnostics(cities: cities))
        } catch {
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
        }
    }

    private func importLibrary(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let importedCities = try exportService.importLibrary(from: url, nextSortIndex: cities.count)
            insertImportedCities(importedCities)
        } catch {
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
        }
    }

    private func importLibrary(fromText text: String) {
        do {
            let importedCities = try exportService.importLibrary(fromText: text, nextSortIndex: cities.count)
            insertImportedCities(importedCities)
        } catch {
            syncErrorMessage = error.localizedDescription
            showingSyncError = true
        }
    }

    private func insertImportedCities(_ importedCities: [CityPlan]) {
        for city in importedCities {
            if let existingCity = cities.first(where: { $0.id == city.id }) {
                modelContext.delete(existingCity)
            }
            modelContext.insert(city)
        }
        showingImportDone = true
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationAuthorizationStatus = await NotificationScheduler().authorizationStatus()
        if notificationAuthorizationStatus == .denied {
            notificationsEnabled = false
        }
    }

    private func testNotifications() {
        Task {
            do {
                try await NotificationScheduler().scheduleTestNotification()
                await refreshNotificationStatus()
                notificationMessage = WaymintLocalization.text("Test je naplánovaný. Za pět sekund se zobrazí banner i při otevřené aplikaci.")
            } catch {
                await refreshNotificationStatus()
                notificationMessage = error.localizedDescription
            }
        }
    }

    private var notificationStatusTitle: LocalizedStringKey {
        switch notificationAuthorizationStatus {
        case .authorized: "Povoleno"
        case .provisional: "Doručováno potichu"
        case .ephemeral: "Dočasně povoleno"
        case .denied: "Zakázáno"
        case .notDetermined: "Není nastaveno"
        @unknown default: "Neznámé"
        }
    }

    private var notificationStatusIcon: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral: "bell.fill"
        case .denied: "bell.slash.fill"
        case .notDetermined: "bell.badge"
        @unknown default: "questionmark.circle"
        }
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { ICloudSyncSettings.isEnabled },
            set: { isEnabled in
                if isEnabled {
                    if !ICloudSyncSettings.isAvailableInCurrentBuild {
                        iCloudSyncEnabled = false
                    } else if iCloudSyncConsentAccepted {
                        iCloudSyncEnabled = true
                    } else {
                        showingICloudConsent = true
                    }
                } else {
                    iCloudSyncEnabled = false
                }
            }
        )
    }

    private var locationAuthorizationTitle: LocalizedStringKey {
        switch locationAuthorizationStatus {
        case .authorizedAlways: "Vždy"
        case .authorizedWhenInUse: "Při používání"
        case .denied: "Zakázáno"
        case .restricted: "Omezeno"
        case .notDetermined: "Není nastaveno"
        @unknown default: "Neznámé"
        }
    }

    private var iCloudStatusTitle: String {
        if !ICloudSyncSettings.isAvailableInCurrentBuild {
            return "iCloud není dostupný v tomto buildu"
        }
        return ICloudSyncSettings.isEnabled ? "iCloud synchronizace je zapnutá" : "Data zůstávají jen v tomto zařízení"
    }

    private var iCloudStatusIcon: String {
        if !ICloudSyncSettings.isAvailableInCurrentBuild {
            return "icloud.slash"
        }
        return ICloudSyncSettings.isEnabled ? "icloud.fill" : "iphone"
    }

    private var iCloudStatusMessage: String {
        if !ICloudSyncSettings.isAvailableInCurrentBuild {
            return "Osobní Apple Team nepodporuje iCloud/CloudKit capability. Aplikace proto používá lokální úložiště. Synchronizaci půjde znovu zapnout po přechodu na placený Apple Developer Program."
        }
        return "Po zapnutí se města, cesty, zastávky, checklisty a metadata vstupenek synchronizují přes soukromý iCloud účet. iOS odesílání řídí automaticky podle připojení a stavu zařízení, typicky na Wi-Fi."
    }
}

private extension UTType {
    static var waymintLibrary: UTType {
        UTType(filenameExtension: "waymint") ?? .json
    }
}

private struct WaymintTextImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var textEditorFocused: Bool
    let onImport: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vlož sem JSON export od AI. Waymint automaticky opraví typografické uvozovky a zpracuje ho stejně jako soubor .waymint.")
                        .font(.footnote)
                        .foregroundStyle(WaymintTheme.secondaryText)

                    HStack {
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("Vložit ze schránky", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()

                        Text(WaymintLocalization.format("%d znaků", text.count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }
                .padding(.horizontal)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($textEditorFocused)
                        .scrollContentBackground(.hidden)
                        .padding(10)

                    if text.isEmpty {
                        Text("Sem vlož JSON text...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(WaymintTheme.secondaryText.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                        .stroke(textEditorFocused ? WaymintTheme.primaryGreen.opacity(0.6) : WaymintTheme.lightGreen, lineWidth: 1)
                }
                .padding(.horizontal)
                .frame(minHeight: 420)
            }
            .padding(.vertical)
            .background(WaymintTheme.surface)
            .navigationTitle("Vložit AI text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importovat") {
                        onImport(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let clipboardText = UIPasteboard.general.string,
                   text.isEmpty,
                   clipboardText.contains("waymint.library") {
                    text = clipboardText
                }
            }
        }
    }

    private func pasteFromClipboard() {
        if let clipboardText = UIPasteboard.general.string {
            text = clipboardText
        }
    }
}
