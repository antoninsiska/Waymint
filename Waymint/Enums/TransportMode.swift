import Foundation

enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case walking
    case publicTransport
    case car
    case taxi
    case train
    case bike
    case boat
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: "Pěšky"
        case .publicTransport: "MHD"
        case .car: "Auto"
        case .taxi: "Taxi"
        case .train: "Vlak"
        case .bike: "Kolo"
        case .boat: "Loď"
        case .other: "Jiné"
        }
    }

    var systemImage: String {
        switch self {
        case .walking: "figure.walk"
        case .publicTransport: "tram.fill"
        case .car: "car.fill"
        case .taxi: "car.circle"
        case .train: "train.side.front.car"
        case .bike: "bicycle"
        case .boat: "ferry"
        case .other: "ellipsis.circle"
        }
    }
}
