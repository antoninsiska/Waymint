import SwiftData
import SwiftUI

struct CityFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let city: CityPlan?
    let nextSortIndex: Int

    @State private var name = ""
    @State private var country = ""
    @State private var landingTitle = ""
    @State private var landingSubtitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Město") {
                    TextField("Název", text: $name)
                    TextField("Země", text: $country)
                }

                Section("Úvodní stránka") {
                    TextField("Nadpis", text: $landingTitle)
                    TextField("Krátký popis", text: $landingSubtitle, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(Text(LocalizedStringKey(city == nil ? "Nové město" : "Upravit město")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let city else { return }
                name = city.name
                country = city.country
                landingTitle = city.landingTitle
                landingSubtitle = city.landingSubtitle
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)

        if let city {
            city.name = trimmedName
            city.country = trimmedCountry
            city.landingTitle = landingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            city.landingSubtitle = landingSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            city.updatedAt = .now
        } else {
            modelContext.insert(
                CityPlan(
                    name: trimmedName,
                    country: trimmedCountry,
                    landingTitle: landingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    landingSubtitle: landingSubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    sortIndex: nextSortIndex
                )
            )
        }

        dismiss()
    }
}

#Preview {
    CityFormView(city: nil, nextSortIndex: 0)
        .modelContainer(PreviewData.container())
}
