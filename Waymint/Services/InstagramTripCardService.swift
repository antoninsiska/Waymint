import MapKit
import UIKit

@MainActor
struct InstagramTripCardService {
    enum Style: String, CaseIterable, Identifiable {
        case dark, light, map
        var id: String { rawValue }
        var title: String {
            switch self { case .dark: "Tmavý"; case .light: "Světlý"; case .map: "Mapa" }
        }
    }
    enum CardError: LocalizedError {
        case missingCoordinates

        var errorDescription: String? {
            WaymintLocalization.text("Pro obrázek jsou potřeba souřadnice alespoň dvou zastávek.")
        }
    }

    func create(for trip: TripPlan, style: Style = .dark, excludedStopIDs: Set<UUID> = []) async throws -> URL {
        let stops = trip.sortedStops.filter { $0.coordinateIsValid && !excludedStopIDs.contains($0.id) }
        guard stops.count >= 2 else { throw CardError.missingCoordinates }

        let route = await routeCoordinates(for: trip, stops: stops)
        let mapImage = try await snapshot(for: route.coordinates, style: style)
        let image = renderCard(trip: trip, mapImage: mapImage, route: route, style: style)
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Waymint-\(trip.id.uuidString)-\(style.rawValue)-Instagram.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func routeCoordinates(for trip: TripPlan, stops: [TripStop]) async -> (coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance) {
        var result: [CLLocationCoordinate2D] = []
        var totalDistance: CLLocationDistance = 0

        for index in 0..<(stops.count - 1) {
            let start = coordinate(for: stops[index])
            let end = coordinate(for: stops[index + 1])
            let segment = trip.sortedTravelSegments.first { $0.toStopID == stops[index + 1].id }
            let request = MKDirections.Request()
            request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
            request.transportType = (segment?.transportMode ?? .walking).mapKitTransportType

            if let route = try? await MKDirections(request: request).calculate().routes.first {
                var coordinates = [CLLocationCoordinate2D](
                    repeating: kCLLocationCoordinate2DInvalid,
                    count: route.polyline.pointCount
                )
                route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: route.polyline.pointCount))
                if !result.isEmpty { coordinates.removeFirst() }
                result.append(contentsOf: coordinates)
                totalDistance += route.distance
            } else {
                if result.isEmpty { result.append(start) }
                result.append(end)
                totalDistance += CLLocation(latitude: start.latitude, longitude: start.longitude)
                    .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            }
        }
        return (result, totalDistance)
    }

    private func snapshot(for coordinates: [CLLocationCoordinate2D], style: Style) async throws -> MKMapSnapshotter.Snapshot {
        let options = MKMapSnapshotter.Options()
        options.size = CGSize(width: 960, height: 880)
        options.scale = 1
        options.mapType = style == .map ? .hybridFlyover : .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.region = region(for: coordinates)
        return try await MKMapSnapshotter(options: options).start()
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let paddingX = max(rect.size.width * 0.22, 700)
        let paddingY = max(rect.size.height * 0.22, 700)
        return MKCoordinateRegion(rect.insetBy(dx: -paddingX, dy: -paddingY))
    }

    private func renderCard(
        trip: TripPlan,
        mapImage: MKMapSnapshotter.Snapshot,
        route: (coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance),
        style: Style
    ) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let canvas = context.cgContext
            backgroundColor(for: style).setFill()
            canvas.fill(CGRect(origin: .zero, size: size))

            drawBrand(style: style)

            let mapRect = CGRect(x: 60, y: 150, width: 960, height: 880)
            canvas.saveGState()
            UIBezierPath(roundedRect: mapRect, cornerRadius: 42).addClip()
            mapImage.image.draw(in: mapRect)
            UIColor(red: 0.02, green: 0.14, blue: 0.09, alpha: 0.14).setFill()
            canvas.fill(mapRect)

            let path = UIBezierPath()
            for (index, coordinate) in route.coordinates.enumerated() {
                let point = mapImage.point(for: coordinate)
                let adjusted = CGPoint(x: mapRect.minX + point.x, y: mapRect.minY + point.y)
                index == 0 ? path.move(to: adjusted) : path.addLine(to: adjusted)
            }
            path.lineWidth = 12
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (style == .light ? UIColor.white : UIColor.white.withAlphaComponent(0.92)).setStroke()
            path.stroke()
            path.lineWidth = 7
            UIColor(red: 0.10, green: 0.42, blue: 0.27, alpha: 1).setStroke()
            path.stroke()
            canvas.restoreGState()

            let primary = style == .light ? UIColor(red: 0.04, green: 0.16, blue: 0.11, alpha: 1) : UIColor.white
            let secondary = primary.withAlphaComponent(0.58)
            drawText(trip.title, in: CGRect(x: 64, y: 1060, width: 952, height: 80), font: .systemFont(ofSize: 52, weight: .bold), color: primary)
            let subtitle = [trip.city?.name, trip.date.waymintDate].compactMap { $0 }.joined(separator: " · ")
            drawText(subtitle, in: CGRect(x: 64, y: 1132, width: 952, height: 40), font: .systemFont(ofSize: 25, weight: .medium), color: secondary)

            let stats = [
                (WaymintLocalization.text("VZDÁLENOST"), distanceLabel(route.distance)),
                (WaymintLocalization.text("DÉLKA"), trip.approximateDurationMinutes.minutesLabel),
                (WaymintLocalization.text("MÍSTA"), "\(trip.stopCount)")
            ]
            for (index, stat) in stats.enumerated() {
                let x = 64 + CGFloat(index) * 320
                drawText(stat.0, in: CGRect(x: x, y: 1208, width: 290, height: 26), font: .systemFont(ofSize: 18, weight: .semibold), color: secondary)
                drawText(stat.1, in: CGRect(x: x, y: 1240, width: 290, height: 48), font: .systemFont(ofSize: 34, weight: .bold), color: primary)
            }
        }
    }

    private func backgroundColor(for style: Style) -> UIColor {
        switch style {
        case .dark, .map: UIColor(red: 0.035, green: 0.12, blue: 0.085, alpha: 1)
        case .light: UIColor(red: 0.92, green: 0.95, blue: 0.91, alpha: 1)
        }
    }

    private func drawBrand(style: Style) {
        let color = style == .light ? UIColor(red: 0.04, green: 0.16, blue: 0.11, alpha: 1) : UIColor.white
        if let logo = UIImage(named: "WaymintLogo") {
            logo.draw(in: CGRect(x: 60, y: 54, width: 58, height: 58))
        }
        drawText("Waymint", in: CGRect(x: 132, y: 57, width: 250, height: 55), font: .systemFont(ofSize: 34, weight: .bold), color: color)
        drawText(WaymintLocalization.text("MOJE TRASA"), in: CGRect(x: 800, y: 68, width: 216, height: 35), font: .systemFont(ofSize: 18, weight: .bold), color: color.withAlphaComponent(0.52), alignment: .right)
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func distanceLabel(_ meters: CLLocationDistance) -> String {
        if meters >= 1_000 {
            return (meters / 1_000).formatted(.number.precision(.fractionLength(1)).locale(WaymintLocalization.currentLocale)) + " km"
        }
        return Int(meters).formatted(.number.locale(WaymintLocalization.currentLocale)) + " m"
    }

    private func coordinate(for stop: TripStop) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: stop.latitude!, longitude: stop.longitude!)
    }
}
