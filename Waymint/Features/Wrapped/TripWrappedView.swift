import CoreLocation
import SwiftUI
internal import Photos
import UIKit

struct CityWrappedView: View {
    let city: CityPlan

    @State private var photos: [UIImage] = []

    private var stats: CityWrappedStats {
        CityWrappedStats(city: city)
    }

    var body: some View {
        TabView {
            WrappedHeroSlide(city: city, stats: stats, photos: photos)
            WrappedNumberSlide(
                title: "Čas ve městě",
                value: stats.totalCityTimeLabel,
                subtitle: "Součet všech naplánovaných dní ve městě.",
                systemImage: "clock.fill",
                colors: [.green, .mint, .teal]
            )
            WrappedNumberSlide(
                title: "Procestováno",
                value: stats.distanceLabel,
                subtitle: stats.distanceSubtitle,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                colors: [.purple, .blue, .cyan]
            )
            WrappedTopStopSlide(stats: stats, photos: photos)
            WrappedRecapSlide(stats: stats, photos: photos)
        }
        .tabViewStyle(.page)
        .ignoresSafeArea()
        .background(.black)
        .task(id: stats.albumIdentifiers.joined(separator: "|")) {
            photos = await CityWrappedPhotoLoader.loadPhotos(albumIdentifiers: stats.albumIdentifiers, limit: 10)
        }
    }
}

private struct WrappedHeroSlide: View {
    let city: CityPlan
    let stats: CityWrappedStats
    let photos: [UIImage]

    var body: some View {
        WrappedSlideBackground(colors: [.black, Color(red: 0.0, green: 0.28, blue: 0.14), Color(red: 0.03, green: 0.55, blue: 0.25)], photo: photos.first) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer()

                Text("WAYMINT WRAPPED")
                    .font(.caption.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.74))

                Text(city.name)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.64)

                VStack(alignment: .leading, spacing: 10) {
                    WrappedMiniMetric(value: stats.totalCityTimeLabel, label: "ve městě", systemImage: "clock")
                    WrappedMiniMetric(value: stats.distanceLabel, label: "na trase", systemImage: "map")
                    WrappedMiniMetric(value: "\(stats.tripCount)", label: "plánů", systemImage: "calendar")
                    WrappedMiniMetric(value: "\(stats.stopCount)", label: "míst celkem", systemImage: "mappin.and.ellipse")
                }

                Spacer()
            }
            .padding(28)
        }
    }
}

private struct WrappedNumberSlide: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        WrappedSlideBackground(colors: colors, photo: nil) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)

                Text(title.uppercased())
                    .font(.caption.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                Text(value)
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)

                Text(subtitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()
            }
            .padding(28)
        }
    }
}

private struct WrappedTopStopSlide: View {
    let stats: CityWrappedStats
    let photos: [UIImage]

    var body: some View {
        WrappedSlideBackground(colors: [.orange, .pink, .purple], photo: photos.dropFirst().first) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer()

                Text("NEJVÍC ČASU")
                    .font(.caption.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.74))

                Text(stats.longestStopTitle)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.62)

                Text(stats.longestStopDurationLabel)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Tady cesta zpomalila nejvíc. Přesně ten typ místa, kvůli kterému se plán vyplatí.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))

                Spacer()
            }
            .padding(28)
        }
    }
}

private struct WrappedRecapSlide: View {
    let stats: CityWrappedStats
    let photos: [UIImage]

    var body: some View {
        WrappedSlideBackground(colors: [Color(red: 0.05, green: 0.05, blue: 0.05), Color(red: 0.12, green: 0.42, blue: 0.30)], photo: nil) {
            VStack(alignment: .leading, spacing: 18) {
                Text("REKAPITULACE")
                    .font(.caption.weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.72))

                if !photos.isEmpty {
                    WrappedPhotoGrid(photos: photos)
                        .frame(height: 240)
                        .padding(.bottom, 8)
                }

                WrappedRecapRow(value: "\(stats.stopCount)", label: "míst", systemImage: "mappin.and.ellipse")
                WrappedRecapRow(value: "\(stats.tripCount)", label: "plánů", systemImage: "calendar")
                WrappedRecapRow(value: "\(stats.ticketCount)", label: "vstupenek", systemImage: "ticket.fill")
                WrappedRecapRow(value: stats.travelTimeLabel, label: "v přesunech", systemImage: "arrow.right")
                WrappedRecapRow(value: stats.requiredStopRatioLabel, label: "povinných bodů", systemImage: "checkmark.seal.fill")

                Spacer()
            }
            .padding(28)
            .padding(.top, 46)
        }
    }
}

private struct WrappedSlideBackground<Content: View>: View {
    let colors: [Color]
    let photo: UIImage?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.42)
                    .overlay(Color.black.opacity(0.36))
            }

            RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topTrailing, startRadius: 20, endRadius: 260)
                .ignoresSafeArea()

            content
        }
    }
}

private struct WrappedMiniMetric: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        Label {
            Text(value)
                .font(.headline.weight(.black))
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
        } icon: {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.15), in: Capsule())
    }
}

private struct WrappedRecapRow: View {
    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }

            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct WrappedPhotoGrid: View {
    let photos: [UIImage]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(photos.prefix(5).enumerated()), id: \.offset) { index, photo in
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width * (index == 0 ? 0.58 : 0.38), height: index == 0 ? 170 : 112)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(offset(for: index, size: size))
                        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rotation(for index: Int) -> Double {
        [-7, 6, -3, 8, -9][safe: index] ?? 0
    }

    private func offset(for index: Int, size: CGSize) -> CGSize {
        let offsets = [
            CGSize(width: -size.width * 0.12, height: 12),
            CGSize(width: size.width * 0.22, height: -44),
            CGSize(width: size.width * 0.20, height: 72),
            CGSize(width: -size.width * 0.28, height: -70),
            CGSize(width: 0, height: 92)
        ]
        return offsets[safe: index] ?? .zero
    }
}

private struct CityWrappedStats {
    let city: CityPlan

    private var trips: [TripPlan] {
        city.sortedTripPlans.sorted { $0.date < $1.date }
    }

    private var allStops: [TripStop] {
        trips.flatMap(\.sortedStops)
    }

    var tripCount: Int {
        trips.count
    }

    var stopCount: Int {
        allStops.count
    }

    var ticketCount: Int {
        trips.reduce(0) { partial, trip in
            partial + trip.ticketCount + (trip.stops ?? []).reduce(0) { $0 + $1.ticketCount }
        }
    }

    var totalCityTimeMinutes: Int {
        trips.reduce(0) { $0 + $1.approximateDurationMinutes }
    }

    var totalCityTimeLabel: String {
        totalCityTimeMinutes.wrappedDurationLabel
    }

    var travelTimeMinutes: Int {
        trips.reduce(0) { partial, trip in
            partial + (trip.travelSegments ?? []).reduce(0) { $0 + max(0, $1.plannedDurationMinutes + $1.bufferMinutes) }
        }
    }

    var travelTimeLabel: String {
        travelTimeMinutes.wrappedDurationLabel
    }

    var distanceKilometers: Double {
        trips.reduce(0) { partial, trip in
            let coordinates = trip.sortedStops.compactMap { stop -> CLLocationCoordinate2D? in
                guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            guard coordinates.count > 1 else { return partial }
            return partial + zip(coordinates, coordinates.dropFirst()).reduce(0) { distance, pair in
                let from = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                let to = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
                return distance + from.distance(from: to) / 1000
            }
        }
    }

    var distanceLabel: String {
        guard distanceKilometers > 0 else { return "0 km" }
        if distanceKilometers < 10 {
            return "\(distanceKilometers.formatted(.number.precision(.fractionLength(1)))) km"
        }
        return "\(distanceKilometers.formatted(.number.precision(.fractionLength(0)))) km"
    }

    var distanceSubtitle: String {
        distanceKilometers > 0 ? "Odhad podle bodů uložených v mapě." : "Přidej k místům polohu v mapě a Waymint spočítá trasu."
    }

    var longestStop: TripStop? {
        allStops.max { $0.plannedVisitDurationMinutes < $1.plannedVisitDurationMinutes }
    }

    var longestStopTitle: String {
        longestStop?.title ?? "Zatím žádné místo"
    }

    var longestStopDurationLabel: String {
        (longestStop?.plannedVisitDurationMinutes ?? 0).wrappedDurationLabel
    }

    var requiredStopRatioLabel: String {
        guard stopCount > 0 else { return "0 %" }
        let required = allStops.filter(\.isRequired).count
        let ratio = Double(required) / Double(stopCount) * 100
        return "\(ratio.formatted(.number.precision(.fractionLength(0)))) %"
    }

    var albumIdentifiers: [String] {
        Array(Set(trips.compactMap(\.photoAlbumLocalIdentifier))).sorted()
    }
}

private enum CityWrappedPhotoLoader {
    static func loadPhotos(albumIdentifiers: [String], limit: Int) async -> [UIImage] {
        guard !albumIdentifiers.isEmpty else { return [] }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: albumIdentifiers, options: nil)
        guard collections.count > 0 else { return [] }

        var assetsToLoad: [PHAsset] = []
        collections.enumerateObjects { collection, _, _ in
            let options = PHFetchOptions()
            options.fetchLimit = max(1, limit / max(1, albumIdentifiers.count))
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            for index in 0..<assets.count {
                assetsToLoad.append(assets.object(at: index))
            }
        }
        guard !assetsToLoad.isEmpty else { return [] }

        var images: [UIImage] = []
        for asset in assetsToLoad.prefix(limit) {
            if let image = await image(for: asset) {
                images.append(image)
            }
        }
        return images
    }

    private static func image(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 900, height: 1200),
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

private extension Int {
    var wrappedDurationLabel: String {
        if self >= 60 {
            let hours = self / 60
            let minutes = self % 60
            return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
        }
        return minutesLabel
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
