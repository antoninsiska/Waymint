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
                            title: "Zadne album",
                            message: "V Apple Photos jsem nenasel zadne uzivatelske album."
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
                        Label("Photos nejsou povolene", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("Povol pristup k fotkam a vyber album pro tuhle cestu.")
                    } actions: {
                        Button("Povolit pristup") {
                            requestAccess()
                        }
                    }
                }
            }
            .navigationTitle("Album cesty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") { dismiss() }
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
