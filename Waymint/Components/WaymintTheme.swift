import SwiftUI
import UIKit

enum WaymintTheme {
    static let primaryGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.34, green: 0.78, blue: 0.56, alpha: 1)
            : UIColor(red: 0.16, green: 0.45, blue: 0.31, alpha: 1)
    })
    static let darkGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.9, blue: 0.72, alpha: 1)
            : UIColor(red: 0.08, green: 0.23, blue: 0.17, alpha: 1)
    })
    static let lightGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.08, green: 0.22, blue: 0.16, alpha: 1)
            : UIColor(red: 0.79, green: 0.88, blue: 0.81, alpha: 1)
    })
    static let surface = Color(.systemBackground)
    static let elevatedSurface = Color(.secondarySystemBackground)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let warning = Color(red: 0.76, green: 0.46, blue: 0.09)
    static let danger = Color(red: 0.72, green: 0.18, blue: 0.18)
    static let success = Color(red: 0.18, green: 0.54, blue: 0.29)

    static let cornerRadius: CGFloat = 8
}

struct StatusPill: View {
    let text: String
    let systemImage: String?
    let tint: Color

    init(_ text: String, systemImage: String? = nil, tint: Color = WaymintTheme.primaryGreen) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(LocalizedStringKey(text))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label { Text(LocalizedStringKey(title)) } icon: { Image(systemName: systemImage) }
        } description: {
            Text(LocalizedStringKey(message))
        }
    }
}
