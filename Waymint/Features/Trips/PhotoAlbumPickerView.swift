internal import Photos
import SwiftUI

struct PhotoAlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (PHAssetCollection) -> Void

    @State private var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var albums: [PHAssetCollection] = []

    var body: some View {
        NavigationStack {
            Group {
                if authorizationStatus == .authorized || authorizationStatus == .limited {
                    if albums.isEmpty {
                        EmptyStateView(
                            systemImage: "photo.on.rectangle.angled",
                            title: "Žádné album",
                            message: "V Apple Photos jsem nenašel žádné uživatelské album."
                        )
                    } else {
                        List(albums, id: \.localIdentifier) { album in
                            Button {
                                onSelect(album)
                                dismiss()
                            } label: {
                                HStack {
                                    Label(album.localizedTitle ?? "Album", systemImage: "photo.stack")
                                    Spacer()
                                    Text("\(assetCount(for: album))")
                                        .font(.caption)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Fotky nejsou povolené", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("Povol přístup k fotkám a vyber album pro tuto cestu.")
                    } actions: {
                        Button("Povolit přístup") {
                            requestAccess()
                        }
                    }
                }
            }
            .navigationTitle("Album cesty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
            .onAppear {
                if authorizationStatus == .notDetermined {
                    requestAccess()
                } else {
                    loadAlbums()
                }
            }
        }
    }

    private func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            Task { @MainActor in
                authorizationStatus = status
                loadAlbums()
            }
        }
    }

    private func loadAlbums() {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var loadedAlbums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            loadedAlbums.append(collection)
        }
        albums = loadedAlbums.sorted { ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "") }
    }

    private func assetCount(for album: PHAssetCollection) -> Int {
        PHAsset.fetchAssets(in: album, options: nil).count
    }
}
