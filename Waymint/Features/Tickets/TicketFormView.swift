import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct TicketFormView: View {
    @Environment(\.dismiss) private var dismiss

    let trip: TripPlan?
    let stop: TripStop?
    let ticket: TicketItem?

    @State private var title = ""
    @State private var ticketType = TicketType.pdf
    @State private var code = ""
    @State private var note = ""
    @State private var localFilePath: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingPDFImporter = false
    @State private var errorMessage: String?

    private let storage = TicketStorageService()

    init(trip: TripPlan?, stop: TripStop?, ticket: TicketItem? = nil) {
        self.trip = trip
        self.stop = stop
        self.ticket = ticket
        _title = State(initialValue: ticket?.title ?? "")
        _ticketType = State(initialValue: ticket?.ticketType ?? .pdf)
        _code = State(initialValue: ticket?.code ?? ticket?.externalURLString ?? "")
        _note = State(initialValue: ticket?.note ?? "")
        _localFilePath = State(initialValue: ticket?.localFilePath)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TicketFormPreview(
                        title: title.isEmpty ? defaultTitle : title,
                        type: ticketType,
                        hasAttachment: localFilePath != nil,
                        code: code
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Typ vstupenky") {
                    Picker("Typ", selection: $ticketType) {
                        ForEach(TicketType.allCases) { type in
                            Label(type.title, systemImage: icon(for: type)).tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Vstupenka") {
                    TextField("Nazev", text: $title)

                    switch ticketType {
                    case .pdf:
                        Button {
                            showingPDFImporter = true
                        } label: {
                            Label(localFilePath == nil ? "Vybrat PDF soubor" : "PDF vybrano", systemImage: "doc")
                        }
                    case .image, .qrCode, .barcode:
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(localFilePath == nil ? "Vybrat obrazek z galerie" : "Obrazek vybran", systemImage: "photo")
                        }
                    case .textCode, .link:
                        TextField(ticketType == .link ? "Odkaz" : "Kod", text: $code, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(2...5)
                    }

                    if let localFilePath {
                        Label(localFilePath, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.warning)
                    }
                }

                Section("Poznamka") {
                    TextField("Volitelna poznamka", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(ticket == nil ? "Nova vstupenka" : "Upravit vstupenku")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ulozit", action: save)
                        .disabled(!canSave)
                }
            }
            .fileImporter(isPresented: $showingPDFImporter, allowedContentTypes: [.pdf], onCompletion: importFile)
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                importPhoto(newValue)
            }
        }
    }

    private var canSave: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch ticketType {
        case .pdf, .image, .qrCode, .barcode:
            return hasTitle && localFilePath != nil
        case .textCode, .link:
            return hasTitle && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let sourceURL = try result.get()
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let copiedURL = try storage.localURL(forImportedFile: sourceURL)
            localFilePath = copiedURL.path()
            if title.isEmpty {
                title = sourceURL.deletingPathExtension().lastPathComponent
            }
            errorMessage = nil
        } catch {
            errorMessage = "Soubor se nepodarilo ulozit lokalne."
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Obrazek se nepodarilo nacist."
                    return
                }

                let copiedURL = try storage.saveTicketData(data, preferredExtension: "jpg")
                localFilePath = copiedURL.path()
                if title.isEmpty {
                    title = defaultTitle
                }
                errorMessage = nil
            } catch {
                errorMessage = "Obrazek se nepodarilo ulozit lokalne."
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let storesAttachment = ticketType == .pdf || ticketType == .image || ticketType == .qrCode || ticketType == .barcode
        let storedCode = trimmedCode.isEmpty ? nil : trimmedCode
        let storedLocalFilePath = storesAttachment ? localFilePath : nil
        let storedExternalURLString = ticketType == .link ? trimmedCode : nil

        if let ticket {
            ticket.title = trimmedTitle
            ticket.ticketType = ticketType
            ticket.code = storedCode
            ticket.localFilePath = storedLocalFilePath
            ticket.externalURLString = storedExternalURLString
            ticket.note = note
        } else {
            let ticket = TicketItem(
                title: trimmedTitle,
                ticketType: ticketType,
                code: storedCode,
                localFilePath: storedLocalFilePath,
                externalURLString: storedExternalURLString,
                note: note
            )

            if let stop {
                stop.addTicket(ticket)
            }
            if let trip {
                trip.addTicket(ticket)
            }
        }

        dismiss()
    }

    private var defaultTitle: String {
        switch ticketType {
        case .qrCode: "QR kod"
        case .barcode: "Carovy kod"
        case .image: "Obrazek vstupenky"
        default: ticketType.title
        }
    }

    private func icon(for type: TicketType) -> String {
        switch type {
        case .pdf: "doc"
        case .image: "photo"
        case .qrCode: "qrcode"
        case .barcode: "barcode"
        case .textCode: "textformat.abc"
        case .link: "link"
        }
    }
}

private struct TicketFormPreview: View {
    let title: String
    let type: TicketType
    let hasAttachment: Bool
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(type.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Divider()
                .overlay(.white.opacity(0.24))

            HStack {
                Label(statusText, systemImage: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("Waymint")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    WaymintTheme.darkGreen,
                    WaymintTheme.primaryGreen,
                    Color(red: 0.08, green: 0.16, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(alignment: .trailing) {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    Circle()
                        .fill(Color(.systemGroupedBackground))
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.trailing, -4)
        }
    }

    private var statusText: String {
        switch type {
        case .pdf, .image, .qrCode, .barcode:
            hasAttachment ? "Soubor pripraveny" : "Ceka na nahrani"
        case .textCode, .link:
            code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ceka na kod" : "Kod pripraveny"
        }
    }

    private var statusIcon: String {
        switch type {
        case .pdf, .image, .qrCode, .barcode:
            hasAttachment ? "checkmark.seal.fill" : "square.and.arrow.down"
        case .textCode, .link:
            code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "text.cursor" : "checkmark.seal.fill"
        }
    }

    private var icon: String {
        switch type {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .qrCode: "qrcode"
        case .barcode: "barcode"
        case .textCode: "textformat.abc"
        case .link: "link"
        }
    }
}
