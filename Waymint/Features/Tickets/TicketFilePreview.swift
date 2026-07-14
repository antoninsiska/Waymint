import QuickLook
import SwiftUI
import UIKit

struct TicketFilePreview: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: url.path()) {
                    TicketImagePreview(image: image, fileName: url.lastPathComponent)
                } else if FileManager.default.fileExists(atPath: url.path()) {
                    QuickLookPreview(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView {
                        Label("Soubor nejde otevřít", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Vstupenka už v uložených souborech aplikace není dostupná.")
                    }
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TicketImagePreview: View {
    let image: UIImage
    let fileName: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 520)
                    .padding(18)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 12)

                Label(fileName, systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WaymintTheme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(WaymintTheme.elevatedSurface)
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
