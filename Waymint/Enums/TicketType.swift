import Foundation

enum TicketType: String, CaseIterable, Identifiable, Codable {
    case pdf
    case image
    case qrCode
    case barcode
    case textCode
    case link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .image: "Obrazek"
        case .qrCode: "QR kod"
        case .barcode: "Carovy kod"
        case .textCode: "Textovy kod"
        case .link: "Odkaz"
        }
    }
}
