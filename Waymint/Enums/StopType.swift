import Foundation

enum StopType: String, CaseIterable, Identifiable, Codable {
    case hotel
    case museum
    case gallery
    case restaurant
    case food
    case cafe
    case park
    case sight
    case viewpoint
    case trainStation
    case airport
    case transport
    case activity
    case shop
    case custom
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotel: "Hotel"
        case .museum: "Muzeum"
        case .gallery: "Galerie"
        case .restaurant: "Restaurace"
        case .food: "Jidlo"
        case .cafe: "Kavarna"
        case .park: "Park"
        case .sight: "Pamatka"
        case .viewpoint: "Vyhlidka"
        case .trainStation: "Nadrazi"
        case .airport: "Letiste"
        case .transport: "Doprava"
        case .activity: "Aktivita"
        case .shop: "Obchod"
        case .custom: "Vlastni bod"
        case .transfer: "Presun"
        }
    }

    var systemImage: String {
        switch self {
        case .hotel: "bed.double"
        case .museum: "building.columns"
        case .gallery: "photo"
        case .restaurant: "fork.knife"
        case .food: "fork.knife"
        case .cafe: "cup.and.saucer"
        case .park: "leaf"
        case .sight: "building.columns"
        case .viewpoint: "binoculars"
        case .trainStation: "tram.fill"
        case .airport: "airplane"
        case .transport: "tram.fill"
        case .activity: "figure.walk.motion"
        case .shop: "bag"
        case .custom: "mappin.circle"
        case .transfer: "arrow.right"
        }
    }
}
