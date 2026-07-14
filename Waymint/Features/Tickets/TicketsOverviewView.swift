import SwiftData
import SwiftUI
import UIKit

struct TicketsOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: TripPlan
    @State private var selectedTicket: TicketItem?
    @State private var editingTicket: TicketItem?
    @State private var previewURL: URL?
    @State private var showingFilePreview = false
    @State private var ticketToDelete: TicketItem?
    private let storage = TicketStorageService()

    var body: some View {
        ScrollView {
            if trip.sortedTickets.isEmpty {
                EmptyStateView(
                    systemImage: "ticket",
                    title: "Zadne vstupenky",
                    message: "Vstupenky muzes pridat v detailu zastavky nebo sem jako centralni polozku planu."
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(trip.sortedTickets) { ticket in
                        TicketRowView(
                            ticket: ticket,
                            onOpen: { open(ticket) },
                            onEdit: { editingTicket = ticket },
                            onDelete: { ticketToDelete = ticket }
                        )
                    }
                }
                .padding(16)
            }
        }
        .background(WaymintTheme.elevatedSurface)
        .sheet(item: $selectedTicket) { ticket in
            NavigationStack {
                TicketDetailView(
                    ticket: ticket,
                    onOpenFile: { open(ticket) },
                    onEdit: {
                        selectedTicket = nil
                        editingTicket = ticket
                    },
                    onDelete: {
                        selectedTicket = nil
                        ticketToDelete = ticket
                    }
                )
            }
        }
        .sheet(item: $editingTicket) { ticket in
            TicketFormView(trip: ticket.tripPlan, stop: ticket.stop, ticket: ticket)
        }
        .sheet(isPresented: $showingFilePreview) {
            if let previewURL {
                TicketFilePreview(url: previewURL)
            }
        }
        .confirmationDialog("Smazat vstupenku?", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
            Button("Smazat", role: .destructive) {
                if let ticketToDelete {
                    storage.deleteLocalFile(at: ticketToDelete.localFilePath)
                    modelContext.delete(ticketToDelete)
                }
                selectedTicket = nil
                editingTicket = nil
                ticketToDelete = nil
            }
            Button("Zrusit", role: .cancel) {
                ticketToDelete = nil
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { ticketToDelete != nil },
            set: { if !$0 { ticketToDelete = nil } }
        )
    }

    private func open(_ ticket: TicketItem) {
        if let localFilePath = ticket.localFilePath {
            previewURL = URL(filePath: localFilePath)
            showingFilePreview = true
            return
        }
        if ticket.ticketType == .link,
           let externalURLString = ticket.externalURLString ?? ticket.code,
           let url = URL(string: externalURLString) {
            UIApplication.shared.open(url)
            return
        }
        selectedTicket = ticket
    }
}

struct TicketRowView: View {
    let ticket: TicketItem
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconTint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(iconTint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(ticket.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WaymintTheme.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(ticket.ticketType.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(iconTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(iconTint.opacity(0.12), in: Capsule())

                        if let stopTitle = ticket.stop?.title {
                            Text(stopTitle)
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }

            if let code = ticket.code, !code.isEmpty {
                TicketCodePanel(code: code)
            }

            if let localFilePath = ticket.localFilePath {
                HStack(spacing: 10) {
                    Image(systemName: ticket.ticketType == .pdf ? "doc.richtext" : "photo")
                        .foregroundStyle(iconTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticket.ticketType == .pdf ? "Soubor ulozeny v aplikaci" : "Obrazek ulozeny v aplikaci")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WaymintTheme.primaryText)
                        Text(URL(filePath: localFilePath).lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(WaymintTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(WaymintTheme.success)
                }
                .padding(12)
                .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
            }

            if !ticket.note.isEmpty {
                Text(ticket.note)
                    .font(.caption)
                    .foregroundStyle(WaymintTheme.secondaryText)
            }

                HStack(spacing: 8) {
                    TicketActionButton(title: actionTitle, systemImage: actionIcon, tint: iconTint, action: onOpen)
                    TicketActionButton(title: "Upravit", systemImage: "pencil", tint: WaymintTheme.secondaryText, action: onEdit)
                    TicketActionButton(title: "Smazat", systemImage: "trash", tint: WaymintTheme.danger, action: onDelete)
                }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(WaymintTheme.surface)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
        )
        .overlay(alignment: .trailing) {
            VStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { _ in
                    Circle()
                        .fill(WaymintTheme.elevatedSurface)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.trailing, -4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) {
                Label(actionTitle, systemImage: actionIcon)
            }
            Button(action: onEdit) {
                Label("Upravit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Smazat", systemImage: "trash")
            }
        }
    }

    private var icon: String {
        switch ticket.ticketType {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .qrCode: "qrcode"
        case .barcode: "barcode"
        case .textCode: "textformat.abc"
        case .link: "link"
        }
    }

    private var iconTint: Color {
        switch ticket.ticketType {
        case .pdf: WaymintTheme.danger
        case .image: Color(red: 0.35, green: 0.31, blue: 0.74)
        case .qrCode: WaymintTheme.darkGreen
        case .barcode: Color(red: 0.1, green: 0.35, blue: 0.55)
        case .textCode: WaymintTheme.warning
        case .link: WaymintTheme.primaryGreen
        }
    }

    private var actionTitle: String {
        switch ticket.ticketType {
        case .pdf: "Otevrit PDF"
        case .image, .qrCode, .barcode: "Zobrazit"
        case .textCode: "Detail"
        case .link: "Otevrit"
        }
    }

    private var actionIcon: String {
        switch ticket.ticketType {
        case .pdf: "doc.text.magnifyingglass"
        case .image, .qrCode, .barcode: "eye"
        case .textCode: "number"
        case .link: "safari"
        }
    }
}

private struct TicketActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
    }
}

struct TicketDetailView: View {
    let ticket: TicketItem
    let onOpenFile: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TicketRowView(ticket: ticket, onOpen: onOpenFile, onEdit: onEdit, onDelete: onDelete)

                if let code = ticket.code, !code.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ticket.ticketType == .link ? "Odkaz" : "Kod")
                            .font(.headline)
                        TicketCodePanel(code: code)
                    }
                }

                if let localFilePath = ticket.localFilePath {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Soubor")
                            .font(.headline)
                        Button(action: onOpenFile) {
                            Label(URL(filePath: localFilePath).lastPathComponent, systemImage: ticket.ticketType == .pdf ? "doc.richtext" : "photo")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !ticket.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Poznamka")
                            .font(.headline)
                        Text(ticket.note)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }
            }
            .padding(16)
        }
        .background(WaymintTheme.elevatedSurface)
        .navigationTitle(ticket.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onEdit) {
                    Label("Upravit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Smazat", systemImage: "trash")
                }
            }
        }
    }
}

private struct TicketCodePanel: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kod vstupenky")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WaymintTheme.secondaryText)
            Text(code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(WaymintTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(3)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                .fill(WaymintTheme.lightGreen.opacity(0.36))
        )
    }
}

#Preview {
    TicketsOverviewView(trip: TripPlan(title: "Centrum"))
        .modelContainer(PreviewData.container())
}
