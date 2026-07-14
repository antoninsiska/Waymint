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
                Section("Mesto") {
                    TextField("Nazev", text: $name)
                    TextField("Zeme", text: $country)
                }

                Section("Landing page") {
                    TextField("Nadpis", text: $landingTitle)
                    TextField("Kratky popis", text: $landingSubtitle, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(city == nil ? "Nove mesto" : "Upravit mesto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ulozit", action: save)
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
