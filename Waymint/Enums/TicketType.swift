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
        case .image: "Obrázek"
        case .qrCode: "QR kód"
        case .barcode: "Čárový kód"
        case .textCode: "Textový kód"
        case .link: "Odkaz"
        }
    }
}
