import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @AppStorage("waymintPlaceBankEnabled") private var placeBankEnabled = false
    @AppStorage("waymintGPSArrivalRadius") private var gpsArrivalRadius = 85
    @AppStorage("waymintGPSDepartureRadius") private var gpsDepartureRadius = 140
    @AppStorage("waymintGPSDepartureConfirmationSeconds") private var gpsDepartureConfirmationSeconds = 20
    @Environment(\.dismiss) private var dismiss
    @State private var showingICloudConsent = false
    @State private var exportedLibraryFile: ExportedWayFile?
    @State private var importingLibrary = false
    @State private var showingTextImport = false
    @State private var syncErrorMessage = ""
    @State private var showingSyncError = false
    @State private var showingImportDone = false
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
                        Label(iCloudStatusTitle, systemImage: iCloudStatusIcon)
                            .font(.subheadline.weight(.semibold))
                        Text(iCloudStatusMessage)
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }

                Section("Upozornění") {
                    Toggle("Upozornit na odchod a příjezd", isOn: $notificationsEnabled)
                    Text("Waymint může připomenout čas odchodu, správný čas u místa a vstupenky poblíž zastávky.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("GPS automatika") {
                    Stepper("Příchod do \(gpsArrivalRadius) m", value: $gpsArrivalRadius, in: 30...150, step: 5)
                    Stepper("Odchod od \(gpsDepartureRadius) m", value: $gpsDepartureRadius, in: 80...300, step: 10)
                    Stepper("Potvrdit odchod po \(gpsDepartureConfirmationSeconds) s", value: $gpsDepartureConfirmationSeconds, in: 10...60, step: 5)
                    Text("Větší rozdíl mezi příchodem a odchodem omezuje falešné přepnutí při nepřesné GPS.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("Lock Screen a Dynamic Island") {
                    Toggle("Aktuální zastávka", isOn: $showCurrentStop)
                    Toggle("Další zastávka", isOn: $showNextStop)
                    Toggle("Čas odchodu", isOn: $showDepartureTime)
                    Toggle("Zpoždění", isOn: $showDelay)
                }

                Section("Vzhled") {
                    Label("Waymint používá systémový světlý nebo tmavý režim.", systemImage: "circle.lefthalf.filled")
                }

                Section("Nápověda") {
                    Button {
                        hasSeenOnboarding = false
                        dismiss()
                    } label: {
                        Label("Zobrazit průvodce znovu", systemImage: "questionmark.circle")
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
            .sheet(item: $exportedLibraryFile) { file in
                ShareSheet(activityItems: [
                    WaymintFileActivityItem(url: file.url, title: "Waymint záloha")
                ])
            }
            .sheet(isPresented: $showingTextImport) {
                WaymintTextImportView { text in
                    importLibrary(fromText: text)
                }
            }
            .fileImporter(
                isPresented: $importingLibrary,
                allowedContentTypes: [.waymintLibrary, .json],
                allowsMultipleSelection: false,
                onCompletion: importLibrary
            )
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

                        Text("\(text.count) znaků")
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
