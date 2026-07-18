import Combine
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ActiveTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: TripPlan

    @State private var now = Date()
    @StateObject private var liveActivityService = LiveActivityService()
    @StateObject private var locationService = ActiveTripLocationService()
    @State private var completedStopTitle: String?
    @State private var showingCompletionPulse = false
    @State private var showingLiveActivityOptions = false
    @State private var showingStopDetails = false
    @AppStorage("activeTripShowCurrentStop") private var showCurrentStop = true
    @AppStorage("activeTripShowNextStop") private var showNextStop = true
    @AppStorage("activeTripShowDepartureTime") private var showDepartureTime = true
    @AppStorage("activeTripShowDelay") private var showDelay = true
    @AppStorage("waymintNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("waymintActiveTripGPSCorrection") private var gpsCorrectionEnabled = true
    @AppStorage("waymintGPSArrivalRadius") private var gpsArrivalRadius = 85
    @AppStorage("waymintGPSDepartureRadius") private var gpsDepartureRadius = 140
    @AppStorage("waymintGPSDepartureConfirmationSeconds") private var gpsDepartureConfirmationSeconds = 20
    @State private var lastGPSCorrectionAt: Date?
    @State private var lastCorrectedLocation: CLLocation?
    @State private var gpsETA: Date?
    @State private var gpsRoutePolyline: MKPolyline?
    @State private var gpsCorrectionMessage: String?
    @State private var confirmedInsideStopID: UUID?
    @State private var departureCandidateAt: Date?
    @State private var gpsRouteCalculationInProgress = false
    @State private var lastGPSRouteAttemptAt: Date?

    private let delayCalculator = DelayCalculator()
    private let scheduleCalculator = ScheduleCalculator()
    private let notificationScheduler = NotificationScheduler()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stops: [TripStop] {
        trip.sortedStops
    }

    private var currentStop: TripStop? {
        stops.first { $0.status == .active } ??
        stops.first { $0.status == .next } ??
        stops.first { $0.status == .planned }
    }

    private var nextStop: TripStop? {
        guard let currentStop,
              let index = stops.firstIndex(where: { $0.id == currentStop.id }),
              stops.indices.contains(index + 1) else {
            return nil
        }
        return stops[index + 1]
    }

    private var currentStopIndex: Int? {
        guard let currentStop else { return nil }
        return stops.firstIndex { $0.id == currentStop.id }
    }

    private var currentPhase: ActiveTripPhase? {
        guard let currentStop else { return nil }
        if currentStop.status == .active {
            return .atPlace
        }
        return .travelingToPlace
    }


    var body: some View {
        ZStack {
            ActiveTripFullScreenMap(
                currentStop: currentStop,
                nextStop: nextStop,
                userLocation: locationService.location,
                routePolyline: gpsRoutePolyline
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                activeTripTopPanel
                Spacer(minLength: 80)
                activeTripBottomPanel
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay {
            if showingCompletionPulse, let completedStopTitle {
                CompletionPulseView(title: completedStopTitle)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("Aktivní cesta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    endTrip()
                } label: {
                    Label("Ukončit", systemImage: "stop.circle")
                }
            }
        }
        .onAppear {
            prepareTripForStart()
            if stops.allSatisfy({ $0.status == .planned }), let first = stops.first {
                first.status = .active
                first.actualStart = first.actualStart ?? .now
            }
            liveActivityService.refreshStatus()
            startLiveActivity()
            scheduleNotifications()
            if gpsCorrectionEnabled {
                locationService.start()
            }
            consumePendingLiveActivityAction()
        }
        .onChange(of: showCurrentStop) { _, _ in updateLiveActivity() }
        .onChange(of: showNextStop) { _, _ in updateLiveActivity() }
        .onChange(of: showDepartureTime) { _, _ in updateLiveActivity() }
        .onChange(of: showDelay) { _, _ in updateLiveActivity() }
        .onChange(of: gpsCorrectionEnabled) { _, enabled in
            if enabled {
                locationService.start()
            } else {
                locationService.stop()
                gpsETA = nil
                gpsRoutePolyline = nil
                gpsCorrectionMessage = nil
            }
        }
        .onReceive(locationService.$location.compactMap { $0 }) { location in
            guard gpsCorrectionEnabled else { return }
            Task { await correctSchedule(using: location) }
        }
        .onReceive(timer) { date in
            now = date
            autoSwitchArrivedStop()
            updateLiveActivity()
        }
        .onDisappear {
            locationService.stop()
        }
    }

    private var activeTripTopPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(phasePrimaryText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(WaymintTheme.darkGreen)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let currentStop {
                        Text(phaseSubtitle(for: currentStop))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(phaseSubtitleColor(for: currentStop))
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(phasePillText, systemImage: phasePillIcon)
                    if let location = locationService.location {
                        Label("GPS ±\(Int(location.horizontalAccuracy)) m", systemImage: "location.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WaymintTheme.primaryGreen)
                    } else {
                        Label("Čekám na GPS", systemImage: "location.slash")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: tripProgress)
                    .tint(WaymintTheme.primaryGreen)
                HStack {
                    Text("Průběh cesty")
                    Spacer()
                    Text("\(finishedStopCount) z \(stops.count)")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WaymintTheme.secondaryText)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    @ViewBuilder
    private var activeTripBottomPanel: some View {
        if let currentStop {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.snappy) {
                        showingStopDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: currentStop.stopType.systemImage)
                            .font(.title2)
                            .foregroundStyle(WaymintTheme.primaryGreen)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentStopTitle)
                                .font(.headline)
                                .foregroundStyle(WaymintTheme.primaryText)
                                .lineLimit(2)
                            Text(currentPhase == .atPlace ? "Na místě do \(currentStop.plannedDeparture.waymintTime)" : "Příjezd \(currentStop.plannedArrival.waymintTime)")
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: showingStopDetails ? "chevron.down" : "chevron.up")
                            .foregroundStyle(WaymintTheme.primaryGreen)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    ActiveTripActionButton(startActionTitle(for: currentStop), systemImage: startActionIcon(for: currentStop), tint: WaymintTheme.primaryGreen) {
                        start(currentStop)
                    }
                    ActiveTripActionButton("Hotovo", systemImage: "checkmark.circle.fill", tint: WaymintTheme.success) {
                        complete(currentStop)
                    }
                    ActiveTripActionButton("Přeskočit", systemImage: "forward.circle.fill", tint: WaymintTheme.warning) {
                        skip(currentStop)
                    }
                }

                if showingStopDetails {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let message = gpsCorrectionMessage ?? locationService.errorMessage {
                                Label(message, systemImage: "location.circle")
                                    .font(.caption)
                                    .foregroundStyle(WaymintTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Toggle("Průběžná GPS korekce", isOn: $gpsCorrectionEnabled)

                            if !scheduleHistory.isEmpty {
                                DisclosureGroup("Historie přepočtů") {
                                    ForEach(Array(scheduleHistory.suffix(8).reversed()), id: \.self) { entry in
                                        Text(entry)
                                            .font(.caption)
                                            .foregroundStyle(WaymintTheme.secondaryText)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }

                            Button {
                                guard let index = currentStopIndex else { return }
                                recalculateFromArrival(.now, at: index)
                                refreshAfterScheduleChange()
                            } label: {
                                Label("Přepočítat zbývající plán od teď", systemImage: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.bordered)

                            ActiveStopNotesChecklist(stop: currentStop)

                            if let nextStop {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Následuje")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                    ActiveStopSummary(stop: nextStop, showsClockTimes: trip.hasFixedStartTime)
                                }
                            }

                            DisclosureGroup(isExpanded: $showingLiveActivityOptions) {
                                LiveActivityOptionsView(
                                    liveActivityService: liveActivityService,
                                    currentStopExists: true,
                                    showCurrentStop: $showCurrentStop,
                                    showNextStop: $showNextStop,
                                    showDepartureTime: $showDepartureTime,
                                    showDelay: $showDelay,
                                    restart: { startLiveActivity(forceRestart: true) }
                                )
                            } label: {
                                Label("Lock Screen a Dynamic Island", systemImage: liveActivityService.activityID == nil ? "lock" : "lock.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .frame(maxHeight: 310)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }

    private func start(_ stop: TripStop) {
        gpsRoutePolyline = nil
        stop.status = .active
        let arrival = Date()
        stop.actualStart = stop.actualStart ?? arrival
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            recalculateFromArrival(arrival, at: index)
        }
        refreshAfterScheduleChange()
        updateLiveActivity()
    }

    private func complete(_ stop: TripStop) {
        gpsRoutePolyline = nil
        completedStopTitle = stop.title
        withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) {
            showingCompletionPulse = true
        }
        stop.status = .completed
        let departure = Date()
        stop.actualEnd = departure
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            scheduleCalculator.recalculateAfterDeparture(
                departure,
                from: index,
                stops: stops,
                segments: trip.sortedTravelSegments
            )
        }
        markNext(after: stop)
        refreshAfterScheduleChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                showingCompletionPulse = false
            }
        }
    }

    private func skip(_ stop: TripStop) {
        gpsRoutePolyline = nil
        stop.status = .skipped
        let departure = Date()
        stop.actualEnd = departure
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            scheduleCalculator.recalculateAfterDeparture(
                departure,
                from: index,
                stops: stops,
                segments: trip.sortedTravelSegments
            )
        }
        markNext(after: stop)
        refreshAfterScheduleChange()
    }

    private func markNext(after stop: TripStop) {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }),
              stops.indices.contains(index + 1) else {
            trip.status = .completed
            trip.actualEndedAt = .now
            restoreFlexibleStartIfNeeded()
            return
        }
        stops[index + 1].status = .next
    }

    private func autoSwitchArrivedStop() {
        guard trip.hasFixedStartTime else { return }
        guard let currentStop,
              (currentStop.status == .next || currentStop.status == .planned),
              now >= currentStop.plannedArrival else {
            return
        }
        currentStop.status = .active
        currentStop.actualStart = currentStop.actualStart ?? now
        if let index = stops.firstIndex(where: { $0.id == currentStop.id }) {
            recalculateFromArrival(now, at: index)
        }
        refreshAfterScheduleChange()
    }

    private func endTrip() {
        trip.status = .completed
        trip.actualEndedAt = .now
        restoreFlexibleStartIfNeeded()
        Task {
            await liveActivityService.end()
            dismiss()
        }
    }

    private func consumePendingLiveActivityAction() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "waymintPendingLiveActivityTripID") == trip.id.uuidString,
              let action = defaults.string(forKey: "waymintPendingLiveActivityAction"),
              let currentStop else {
            return
        }

        defaults.removeObject(forKey: "waymintPendingLiveActivityAction")
        defaults.removeObject(forKey: "waymintPendingLiveActivityTripID")

        switch action {
        case "start":
            start(currentStop)
        case "complete":
            complete(currentStop)
        case "skip":
            skip(currentStop)
        default:
            break
        }
    }

    private func startLiveActivity(forceRestart: Bool = false) {
        if !forceRestart, liveActivityService.activityID != nil { return }
        guard let currentStop else { return }
        Task {
            await liveActivityService.start(
                trip: trip,
                currentStop: currentStop,
                nextStop: nextStop,
                showCurrentStop: showCurrentStop,
                showNextStop: showNextStop,
                showDepartureTime: showDepartureTime,
                showDelay: showDelay
            )
        }
    }

    private func updateLiveActivity() {
        guard let currentStop else { return }
        Task {
            await liveActivityService.update(
                currentStop: currentStop,
                nextStop: nextStop,
                showCurrentStop: showCurrentStop,
                showNextStop: showNextStop,
                showDepartureTime: showDepartureTime,
                showDelay: showDelay
            )
        }
    }

    private func scheduleNotifications() {
        guard notificationsEnabled, trip.hasFixedStartTime else { return }
        Task {
            _ = try? await notificationScheduler.requestPermissionIfNeeded()
            notificationScheduler.scheduleTripNotifications(for: trip)
        }
    }

    private func recalculateFromArrival(_ arrival: Date, at index: Int) {
        scheduleCalculator.recalculateFromArrival(
            arrival,
            at: index,
            stops: stops,
            segments: trip.sortedTravelSegments
        )
    }

    private func prepareTripForStart() {
        let startedAt = trip.actualStartedAt ?? Date()
        trip.status = .active
        trip.actualStartedAt = startedAt
        trip.actualEndedAt = nil

        guard !trip.hasFixedStartTime else { return }
        trip.hasTemporaryActiveStartTime = true
        trip.hasFixedStartTime = true
        trip.startTime = startedAt
        trip.date = startedAt
        scheduleCalculator.recalculateTrip(trip, anchor: startedAt)
    }

    private func restoreFlexibleStartIfNeeded() {
        guard trip.hasTemporaryActiveStartTime else { return }
        trip.hasTemporaryActiveStartTime = false
        trip.hasFixedStartTime = false
        trip.updatedAt = .now
    }

    private var finishedStopCount: Int {
        stops.filter { $0.status == .completed || $0.status == .skipped }.count
    }

    private var tripProgress: Double {
        guard !stops.isEmpty else { return 0 }
        return Double(finishedStopCount) / Double(stops.count)
    }

    private func refreshAfterScheduleChange() {
        trip.updatedAt = .now
        scheduleNotifications()
        updateLiveActivity()
    }

    private func correctSchedule(using location: CLLocation) async {
        guard let currentStop else { return }
        guard location.horizontalAccuracy >= 0 else { return }
        guard location.horizontalAccuracy <= 120 else {
            gpsCorrectionMessage = "GPS signál je zatím příliš nepřesný (±\(Int(location.horizontalAccuracy)) m). Čekám na přesnější polohu."
            departureCandidateAt = nil
            return
        }

        if currentStop.status == .active {
            if let latitude = currentStop.latitude,
               let longitude = currentStop.longitude {
                let distance = Int(location.distance(from: CLLocation(latitude: latitude, longitude: longitude)))
                if distance <= gpsArrivalRadius {
                    confirmedInsideStopID = currentStop.id
                    departureCandidateAt = nil
                    gpsCorrectionMessage = "Na místě · \(distance) m od \(currentStop.title). Čas návštěvy běží."
                } else if confirmedInsideStopID == currentStop.id, distance >= gpsDepartureRadius {
                    if let departureCandidateAt,
                       Date().timeIntervalSince(departureCandidateAt) >= Double(gpsDepartureConfirmationSeconds) {
                        gpsCorrectionMessage = "Waymint rozpoznal odchod z \(currentStop.title)."
                        recordScheduleChange("GPS: odchod z \(currentStop.title)")
                        confirmedInsideStopID = nil
                        self.departureCandidateAt = nil
                        complete(currentStop)
                    } else if departureCandidateAt == nil {
                        self.departureCandidateAt = .now
                        gpsCorrectionMessage = "Ověřuji odchod z \(currentStop.title)…"
                    }
                } else {
                    departureCandidateAt = nil
                    gpsCorrectionMessage = "GPS je aktivní · \(distance) m od \(currentStop.title)."
                }
            } else {
                gpsCorrectionMessage = "GPS je aktivní. Aktuální zastávka nemá uložené souřadnice."
            }
            return
        }

        guard currentStop.status == .next || currentStop.status == .planned,
              let latitude = currentStop.latitude,
              let longitude = currentStop.longitude,
              let index = stops.firstIndex(where: { $0.id == currentStop.id }) else {
            return
        }

        if let lastGPSCorrectionAt,
           Date().timeIntervalSince(lastGPSCorrectionAt) < 35,
           let lastCorrectedLocation,
           location.distance(from: lastCorrectedLocation) < 40 {
            return
        }

        let destination = CLLocation(latitude: latitude, longitude: longitude)
        let distance = location.distance(from: destination)
        if distance <= Double(gpsArrivalRadius) {
            currentStop.status = .active
            currentStop.actualStart = currentStop.actualStart ?? .now
            confirmedInsideStopID = currentStop.id
            departureCandidateAt = nil
            recalculateFromArrival(.now, at: index)
            gpsETA = .now
            gpsRoutePolyline = nil
            gpsCorrectionMessage = "Waymint rozpoznal příchod na \(currentStop.title)."
            recordScheduleChange("GPS: příchod na \(currentStop.title), plán přepočítán")
            lastGPSCorrectionAt = .now
            lastCorrectedLocation = location
            refreshAfterScheduleChange()
            return
        }

        guard !gpsRouteCalculationInProgress else { return }
        if let lastGPSRouteAttemptAt,
           Date().timeIntervalSince(lastGPSRouteAttemptAt) < 45 {
            return
        }
        lastGPSRouteAttemptAt = .now
        gpsRouteCalculationInProgress = true
        defer { gpsRouteCalculationInProgress = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: location, address: nil)
        request.destination = MKMapItem(location: destination, address: nil)
        let inboundSegment = trip.sortedTravelSegments.first { $0.toStopID == currentStop.id }
        request.transportType = (inboundSegment?.transportMode ?? .walking).mapKitTransportType

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }
            gpsRoutePolyline = route.polyline
            let arrival = Date().addingTimeInterval(route.expectedTravelTime)
            if let inboundSegment,
               index > 0 {
                let elapsedAndRemainingMinutes = max(
                    0,
                    Int(ceil(arrival.timeIntervalSince(stops[index - 1].plannedDeparture) / 60))
                )
                inboundSegment.plannedDurationMinutes = max(
                    0,
                    elapsedAndRemainingMinutes - inboundSegment.bufferMinutes
                )
            }
            recalculateFromArrival(arrival, at: index)
            gpsETA = arrival
            gpsCorrectionMessage = "GPS odhad: \(Int(route.distance)) m, příjezd v \(arrival.waymintTime)."
            recordScheduleChange("GPS: nový odhad příjezdu na \(currentStop.title) v \(arrival.waymintTime)")
            lastGPSCorrectionAt = .now
            lastCorrectedLocation = location
            refreshAfterScheduleChange()
        } catch {
            gpsCorrectionMessage = "GPS funguje, ale Apple Mapy teď nedokázaly spočítat trasu."
        }
    }

    private var phasePrimaryText: String {
        if !trip.hasFixedStartTime, let actualStartedAt = trip.actualStartedAt {
            return elapsedMinutes(since: actualStartedAt).minutesLabel
        }
        guard let currentStop else { return now.waymintTime }
        switch currentPhase {
        case .atPlace:
            return minutesUntil(currentStop.plannedDeparture).minutesLabel
        case .travelingToPlace:
            return minutesUntil(currentStop.plannedArrival).minutesLabel
        case nil:
            return now.waymintTime
        }
    }

    private var phasePillText: String {
        if !trip.hasFixedStartTime, trip.actualStartedAt != nil {
            return "Délka cesty"
        }
        switch currentPhase {
        case .atPlace:
            return "Čas na místě"
        case .travelingToPlace:
            return "Dojezd tam"
        case nil:
            return trip.status.title
        }
    }

    private var phasePillIcon: String {
        if !trip.hasFixedStartTime, trip.actualStartedAt != nil {
            return "timer"
        }
        switch currentPhase {
        case .atPlace:
            return "timer"
        case .travelingToPlace:
            return "arrow.triangle.turn.up.right.diamond.fill"
        case nil:
            return "play.fill"
        }
    }

    private var currentStopTitle: String {
        guard let currentStop else { return "" }
        if currentStopIndex == 0 {
            return "Start: \(currentStop.title)"
        }
        return currentStop.title
    }

    private func phaseSubtitle(for stop: TripStop) -> String {
        guard trip.hasFixedStartTime else {
            switch currentPhase {
            case .atPlace:
                return stop.plannedVisitDurationMinutes > 0 ? "Jsi na místě. Doporučená délka je \(stop.plannedVisitDurationMinutes.minutesLabel)." : "Jsi na startu cesty."
            case .travelingToPlace:
                return "Pokračuj na další bod bez pevně daného času."
            case nil:
                return ""
            }
        }
        switch currentPhase {
        case .atPlace:
            let summary = delayCalculator.delay(now: now, plannedTime: stop.plannedDeparture)
            if summary.isDelayed {
                return "Odchod byl plánovaný v \(stop.plannedDeparture.waymintTime). \(summary.message)"
            }
            return "Odchod v \(stop.plannedDeparture.waymintTime)."
        case .travelingToPlace:
            let summary = delayCalculator.delay(now: now, plannedTime: stop.plannedArrival)
            if summary.isDelayed {
                return "Příjezd byl plánovaný v \(stop.plannedArrival.waymintTime). \(summary.message)"
            }
            return "Příjezd v \(stop.plannedArrival.waymintTime)."
        case nil:
            return ""
        }
    }

    private func phaseSubtitleColor(for stop: TripStop) -> Color {
        guard trip.hasFixedStartTime else {
            return WaymintTheme.secondaryText
        }
        switch currentPhase {
        case .atPlace:
            return delayCalculator.delay(now: now, plannedTime: stop.plannedDeparture).isDelayed ? WaymintTheme.warning : WaymintTheme.success
        case .travelingToPlace:
            return delayCalculator.delay(now: now, plannedTime: stop.plannedArrival).isDelayed ? WaymintTheme.warning : WaymintTheme.success
        case nil:
            return WaymintTheme.secondaryText
        }
    }

    private func startActionTitle(for stop: TripStop) -> String {
        stop.status == .next || stop.status == .planned ? "Dorazil jsem" : "Start"
    }

    private func startActionIcon(for stop: TripStop) -> String {
        stop.status == .next || stop.status == .planned ? "mappin.circle.fill" : "play.circle.fill"
    }

    private func minutesUntil(_ date: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
    }

    private func elapsedMinutes(since date: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }

    private var scheduleHistory: [String] {
        trip.scheduleChangeHistoryText.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private func recordScheduleChange(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var entries = scheduleHistory
        entries.append("\(formatter.string(from: .now)) · \(message)")
        trip.scheduleChangeHistoryText = entries.suffix(40).joined(separator: "\n")
        trip.updatedAt = .now
    }
}

private enum ActiveTripPhase: Equatable {
    case travelingToPlace
    case atPlace
}

private struct ActiveTripFullScreenMap: View {
    let currentStop: TripStop?
    let nextStop: TripStop?
    let userLocation: CLLocation?
    let routePolyline: MKPolyline?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            if let routePolyline {
                MapPolyline(routePolyline)
                    .stroke(
                        WaymintTheme.darkGreen,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
            }
            UserAnnotation()
            if let currentStop,
               let coordinate = coordinate(for: currentStop) {
                Marker(currentStop.title, systemImage: "mappin.circle.fill", coordinate: coordinate)
                    .tint(WaymintTheme.primaryGreen)
            }
            if let nextStop,
               nextStop.id != currentStop?.id,
               let coordinate = coordinate(for: nextStop) {
                Marker(nextStop.title, systemImage: "flag.fill", coordinate: coordinate)
                    .tint(WaymintTheme.darkGreen)
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onChange(of: userLocation) { _, location in
            guard let location else { return }
            position = .region(region(centeredOn: location.coordinate))
        }
    }

    private func region(centeredOn userCoordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        guard let currentStop,
              let destination = coordinate(for: currentStop) else {
            return MKCoordinateRegion(
                center: userCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )
        }

        let center = CLLocationCoordinate2D(
            latitude: (userCoordinate.latitude + destination.latitude) / 2,
            longitude: (userCoordinate.longitude + destination.longitude) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.008, abs(userCoordinate.latitude - destination.latitude) * 1.8),
                longitudeDelta: max(0.008, abs(userCoordinate.longitude - destination.longitude) * 1.8)
            )
        )
    }

    private func coordinate(for stop: TripStop) -> CLLocationCoordinate2D? {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct ActiveTripMapCard: View {
    let currentStop: TripStop
    let nextStop: TripStop?
    let userLocation: CLLocation?
    let gpsETA: Date?
    @Binding var correctionEnabled: Bool
    let correctionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("GPS korekce a mapa", systemImage: "location.fill")
                    .font(.headline)
                Spacer()
                Toggle("GPS korekce", isOn: $correctionEnabled)
                    .labelsHidden()
            }

            Map {
                UserAnnotation()
                if let coordinate = coordinate(for: currentStop) {
                    Marker(currentStop.title, systemImage: "mappin.circle.fill", coordinate: coordinate)
                        .tint(WaymintTheme.primaryGreen)
                }
                if let nextStop,
                   nextStop.id != currentStop.id,
                   let coordinate = coordinate(for: nextStop) {
                    Marker(nextStop.title, systemImage: "flag.fill", coordinate: coordinate)
                        .tint(WaymintTheme.darkGreen)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))

            HStack(spacing: 12) {
                if let userLocation {
                    Label("±\(Int(userLocation.horizontalAccuracy)) m", systemImage: "scope")
                } else {
                    Label("Čekám na polohu", systemImage: "location.slash")
                }
                if let gpsETA {
                    Label("Příjezd \(gpsETA.waymintTime)", systemImage: "clock")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WaymintTheme.secondaryText)

            if let correctionMessage {
                Text(correctionMessage)
                    .font(.caption)
                    .foregroundStyle(WaymintTheme.secondaryText)
            }
        }
        .padding(16)
        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                .stroke(WaymintTheme.lightGreen, lineWidth: 1)
        }
    }

    private func coordinate(for stop: TripStop) -> CLLocationCoordinate2D? {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct CompletionPulseView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .bold))
                .symbolEffect(.bounce)
                .foregroundStyle(WaymintTheme.success)
            Text("Hotovo")
                .font(.title2.weight(.bold))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(WaymintTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
        .padding()
    }
}

private struct ActiveStopNotesChecklist: View {
    @Bindable var stop: TripStop

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Poznámky a checklist", systemImage: "checklist")
                .font(.headline)

            if !stop.mainReason.isEmpty {
                Text(stop.mainReason)
                    .font(.subheadline.weight(.semibold))
            }

            if !stop.note.isEmpty {
                Text(stop.note)
                    .font(.subheadline)
                    .foregroundStyle(WaymintTheme.secondaryText)
            }

            if stop.sortedChecklistItems.isEmpty && stop.note.isEmpty && stop.mainReason.isEmpty {
                Text("Pro tuhle zastávku zatím nejsou poznámky ani checklist.")
                    .font(.subheadline)
                    .foregroundStyle(WaymintTheme.secondaryText)
            } else {
                ForEach(stop.sortedChecklistItems) { item in
                    Button {
                        item.isDone.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? WaymintTheme.success : WaymintTheme.secondaryText)
                            Text(item.title)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? WaymintTheme.secondaryText : WaymintTheme.primaryText)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                .stroke(WaymintTheme.lightGreen, lineWidth: 1)
        }
    }
}

private struct LiveActivityOptionsView: View {
    @ObservedObject var liveActivityService: LiveActivityService
    let currentStopExists: Bool
    @Binding var showCurrentStop: Bool
    @Binding var showNextStop: Bool
    @Binding var showDepartureTime: Bool
    @Binding var showDelay: Bool
    let restart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(liveActivityService.statusMessage)
                .font(.caption)
                .foregroundStyle(WaymintTheme.secondaryText)

            Text("Dynamic Island není vidět, když je aplikace otevřená v popředí. Po spuštění přejdi na Home Screen nebo zamkni zařízení.")
                .font(.caption2)
                .foregroundStyle(WaymintTheme.secondaryText)

            Toggle("Aktuální zastávka", isOn: $showCurrentStop)
            Toggle("Další zastávka", isOn: $showNextStop)
            Toggle("Čas odchodu", isOn: $showDepartureTime)
            Toggle("Zpoždění", isOn: $showDelay)

            HStack {
                Button(action: restart) {
                    Label(liveActivityService.activityID == nil ? "Spustit" : "Restartovat", systemImage: "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!currentStopExists)

                if liveActivityService.activityID != nil {
                    Button(role: .destructive) {
                        Task { await liveActivityService.end() }
                    } label: {
                        Label("Ukončit", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let errorMessage = liveActivityService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(WaymintTheme.warning)
            }
        }
        .padding(.top, 8)
    }
}

private struct ActiveStopSummary: View {
    let stop: TripStop
    let showsClockTimes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stop.title)
                    .font(.headline)
                Spacer()
                StatusPill(stop.status.title)
            }
            Text(scheduleText)
                .foregroundStyle(WaymintTheme.secondaryText)
            Text(remainingText)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private var isTravelingToStop: Bool {
        stop.status == .next || stop.status == .planned
    }

    private var scheduleText: String {
        guard showsClockTimes else {
            if isTravelingToStop {
                return "Další bod · na místě \(stop.plannedVisitDurationMinutes.minutesLabel)"
            }
            return stop.plannedVisitDurationMinutes > 0 ? "Na místě \(stop.plannedVisitDurationMinutes.minutesLabel)" : "Start cesty"
        }
        if isTravelingToStop {
            return "Příjezd \(stop.plannedArrival.waymintTime) · potom na místě \(stop.plannedVisitDurationMinutes.minutesLabel)"
        }
        return "Na místě do \(stop.plannedDeparture.waymintTime)"
    }

    private var remainingText: String {
        guard showsClockTimes else {
            return isTravelingToStop ? "Čas se počítá od spuštění cesty." : "Cesta běží bez pevného odchodu."
        }
        if isTravelingToStop {
            return "Do příjezdu zbývá \(minutesUntil(stop.plannedArrival).minutesLabel)."
        }
        return "Do odchodu zbývá \(minutesUntil(stop.plannedDeparture).minutesLabel)."
    }

    private func minutesUntil(_ date: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSince(.now) / 60)))
    }
}

private struct ActiveTripActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
        .accessibilityLabel(title)
    }
}
#Preview {
    NavigationStack {
        ActiveTripView(trip: TripPlan(title: "Centrum"))
    }
    .modelContainer(PreviewData.container())
}
