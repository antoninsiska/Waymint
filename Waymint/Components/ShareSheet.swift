import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExportedWayFile: Identifiable {
    let id = UUID()
    let url: URL
}

final class WaymintFileActivityItem: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        WaymintShareThumbnail.draw(size: size)
    }
}

private enum WaymintShareThumbnail {
    static func draw(size: CGSize) -> UIImage {
        let dimension = max(64, min(size.width, size.height))
        let canvasSize = CGSize(width: dimension, height: dimension)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: canvasSize)
            UIColor(red: 0.04, green: 0.16, blue: 0.11, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: dimension * 0.22).fill()

            let markRect = rect.insetBy(dx: dimension * 0.18, dy: dimension * 0.28)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: dimension * 0.28, weight: .black),
                .foregroundColor: UIColor(red: 0.41, green: 0.92, blue: 0.68, alpha: 1),
                .kern: -1
            ]
            let text = "WM" as NSString
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: markRect.midX - textSize.width / 2,
                y: markRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
