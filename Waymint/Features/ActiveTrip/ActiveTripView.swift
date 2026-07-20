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
    @State private var showingTimeExplanation = false
    @State private var showingScheduleHistory = false
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
    @AppStorage("waymintEmergencyPowerMode") private var emergencyPowerMode = true
    @AppStorage("waymintKeepScreenAwakeDuringTrip") private var keepScreenAwake = false
    @State private var lastGPSCorrectionAt: Date?
    @State private var lastCorrectedLocation: CLLocation?
    @State private var gpsETA: Date?
    @State private var gpsRoutePolyline: MKPolyline?
    @State private var plannedRouteLines: [TripMapRouteLine] = []
    @State private var gpsCorrectionMessage: String?
    @State private var confirmedInsideStopID: UUID?
    @State private var departureCandidateAt: Date?
    @State private var gpsRouteCalculationInProgress = false
    @State private var lastGPSRouteAttemptAt: Date?
    @State private var lastScheduleSnapshot: ActiveScheduleSnapshot?
    @State private var undoExpiresAt: Date?
    @State private var showingTripSummary = false

    private let delayCalculator = DelayCalculator()
    private let scheduleCalculator = ScheduleCalculator()
    private let notificationScheduler = NotificationScheduler()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stops: [TripStop] {
        trip.sortedStops
    }

    private var plannedRouteSignature: String {
        guard let currentStop else { return "none" }
        return "\(currentStop.id.uuidString):\(currentStop.status.rawValue):\(currentStop.latitude ?? 0):\(currentStop.longitude ?? 0):\(nextStop?.id.uuidString ?? "-")"
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

    private var activePlannedRouteLines: [TripMapRouteLine] {
        plannedRouteLines
    }

    private func plannedLinesForCurrentPhase() async -> [TripMapRouteLine] {
        guard let currentStop,
              let index = stops.firstIndex(where: { $0.id == currentStop.id }) else {
            return []
        }
        if currentStop.status == .active, let nextStop {
            return await TripMapRouteBuilder.routeLines(for: trip, from: currentStop, to: nextStop)
        }
        guard index > 0 else { return [] }
        return await TripMapRouteBuilder.routeLines(for: trip, from: stops[index - 1], to: currentStop)
    }


    var body: some View {
        ZStack {
            ActiveTripFullScreenMap(
                currentStop: currentStop,
                nextStop: nextStop,
                userLocation: locationService.location,
                routePolyline: gpsRoutePolyline,
                plannedRouteLines: activePlannedRouteLines
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
                Menu {
                    Button {
                        togglePause()
                    } label: {
                        Label(trip.status == .paused ? "Pokračovat" : "Pozastavit", systemImage: trip.status == .paused ? "play.fill" : "pause.fill")
                    }
                    Button(role: .destructive) {
                        stopTrip()
                    } label: {
                        Label("Zastavit cestu", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: trip.status == .paused ? "play.circle.fill" : "ellipsis.circle")
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
            prepareTripForStart()
            locationService.configure(lowPower: emergencyPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled)
            if stops.allSatisfy({ $0.status == .planned }), let first = stops.first {
                first.status = .active
                first.actualStart = first.actualStart ?? .now
            }
            liveActivityService.refreshStatus()
            startLiveActivity()
            scheduleNotifications()
            if trip.status != .paused && gpsCorrectionEnabled {
                locationService.start()
            }
            consumePendingLiveActivityAction()
            consumePendingVoiceAction()
            updateVoiceSnapshot()
        }
        .task(id: plannedRouteSignature) {
            plannedRouteLines = await plannedLinesForCurrentPhase()
        }
        .onChange(of: showCurrentStop) { _, _ in updateLiveActivity() }
        .onChange(of: showNextStop) { _, _ in updateLiveActivity() }
        .onChange(of: showDepartureTime) { _, _ in updateLiveActivity() }
        .onChange(of: showDelay) { _, _ in updateLiveActivity() }
        .onChange(of: gpsCorrectionEnabled) { _, enabled in
            if enabled {
                if trip.status != .paused { locationService.start() }
            } else {
                locationService.stop()
                gpsETA = nil
                gpsRoutePolyline = nil
                gpsCorrectionMessage = nil
            }
        }
        .onChange(of: keepScreenAwake) { _, enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .onReceive(locationService.$location.compactMap { $0 }) { location in
            guard gpsCorrectionEnabled else { return }
            Task { await correctSchedule(using: location) }
        }
        .onReceive(timer) { date in
            now = date
            updateVoiceSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waymintVoiceAction)) { notification in
            guard let rawValue = notification.object as? String else { return }
            consumeVoiceAction(rawValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            locationService.configure(lowPower: emergencyPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled)
        }
        .onDisappear {
            locationService.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showingTripSummary) {
            ActiveTripCompletionSummary(trip: trip)
        }
        .sheet(isPresented: $showingTimeExplanation) {
            timeExplanationSheet
        }
        .sheet(isPresented: $showingScheduleHistory) {
            scheduleHistorySheet
        }
        .sheet(isPresented: $showingLiveActivityOptions) {
            liveActivitySettingsSheet
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
                        Label(gpsQuality.label, systemImage: gpsQuality.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(gpsQuality.color)
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
                    Text(WaymintLocalization.format("%d z %d", finishedStopCount, stops.count))
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentStopTitle)
                                .font(.headline)
                                .foregroundStyle(WaymintTheme.primaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: showingStopDetails ? "chevron.down" : "chevron.up")
                            .foregroundStyle(WaymintTheme.primaryGreen)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    if currentStop.status == .next || currentStop.status == .planned {
                        ActiveTripActionButton("Dorazil jsem", systemImage: "mappin.circle.fill", tint: WaymintTheme.primaryGreen) {
                            start(currentStop)
                        }
                    } else {
                        ActiveTripActionButton("Hotovo", systemImage: "checkmark.circle.fill", tint: WaymintTheme.success) {
                            complete(currentStop)
                        }
                    }
                    Menu {
                        if currentStop.coordinateIsValid {
                            Button {
                                openCurrentStopInMaps(currentStop)
                            } label: {
                                Label("Navigovat v Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            }
                        }

                        if let startStop = stops.first, startStop.id != currentStop.id, startStop.coordinateIsValid {
                            Button {
                                openCurrentStopInMaps(startStop)
                            } label: {
                                Label("Bezpečný návrat na start", systemImage: "house.and.flag")
                            }
                        }

                        ShareLink(item: shareStatusText(for: currentStop)) {
                            Label("Sdílet stav cesty", systemImage: "square.and.arrow.up")
                        }

                        Menu("Najít poblíž", systemImage: "sparkle.magnifyingglass") {
                            Button("Toalety", systemImage: "figure.dress.line.vertical.figure") {
                                openNearbySearch("toilet", fallbackStop: currentStop)
                            }
                            Button("Jídlo", systemImage: "fork.knife") {
                                openNearbySearch("restaurant", fallbackStop: currentStop)
                            }
                            Button("Lékárna", systemImage: "cross.case") {
                                openNearbySearch("pharmacy", fallbackStop: currentStop)
                            }
                        }

                        Divider()

                        Button {
                            showingTimeExplanation = true
                        } label: {
                            Label("Proč tento čas?", systemImage: "questionmark.circle")
                        }

                        if !scheduleHistory.isEmpty {
                            Button {
                                showingScheduleHistory = true
                            } label: {
                                Label("Historie přepočtů", systemImage: "clock.arrow.2.circlepath")
                            }
                        }

                        Button {
                            restoreLastScheduleSnapshot()
                        } label: {
                            Label("Vrátit poslední GPS změnu", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(lastScheduleSnapshot == nil || undoExpiresAt.map { $0 <= now } != false)

                        Button {
                            guard let index = currentStopIndex else { return }
                            recalculateFromArrival(.now, at: index)
                            refreshAfterScheduleChange()
                        } label: {
                            Label("Přepočítat zbývající plán od teď", systemImage: "clock.arrow.circlepath")
                        }

                        Button {
                            addQuickPause(minutes: 10, at: currentStop)
                        } label: {
                            Label("Přidat 10 minut pauzu", systemImage: "cup.and.heat.waves")
                        }

                        if departureCandidateAt != nil {
                            Button {
                                departureCandidateAt = nil
                                gpsCorrectionMessage = WaymintLocalization.text("Automatický odchod byl zrušen.")
                            } label: {
                                Label("Zrušit rozpoznávání odchodu", systemImage: "location.slash")
                            }
                        }

                        Divider()

                        Toggle("Průběžná GPS korekce", isOn: $gpsCorrectionEnabled)
                        Toggle("Nechat displej zapnutý", isOn: $keepScreenAwake)

                        Button {
                            showingLiveActivityOptions = true
                        } label: {
                            Label("Lock Screen a Dynamic Island", systemImage: "lock.display")
                        }

                        Divider()

                        Button(role: .destructive) {
                            skip(currentStop)
                        } label: {
                            Label("Přeskočit", systemImage: "forward.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 48, height: 48)
                            .foregroundStyle(WaymintTheme.secondaryText)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .disabled(trip.status == .paused)
                .opacity(trip.status == .paused ? 0.55 : 1)

                if trip.status == .paused {
                    Label("Cesta je pozastavená. GPS automatika, přepočty a oznámení čekají.", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WaymintTheme.warning)
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

                            ActiveStopNotesChecklist(stop: currentStop)

                            if let nextStop {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Následuje")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                    ActiveStopSummary(stop: nextStop, showsClockTimes: trip.hasFixedStartTime)
                                }
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

    private var timeExplanationSheet: some View {
        NavigationStack {
            List {
                if let currentStop {
                    Label(WaymintLocalization.format("Plánovaný příjezd: %@", currentStop.plannedArrival.waymintTime), systemImage: "calendar")
                    Label(WaymintLocalization.format("Plánovaný odchod: %@", currentStop.plannedDeparture.waymintTime), systemImage: "clock")
                    if let actualStart = currentStop.actualStart {
                        Label(WaymintLocalization.format("Skutečný příchod: %@", actualStart.waymintTime), systemImage: "mappin.and.ellipse")
                    }
                    if let gpsETA {
                        Label(WaymintLocalization.format("Poslední GPS odhad: %@", gpsETA.waymintTime), systemImage: "location.fill")
                    }
                    if let latest = scheduleHistory.last {
                        Section("Poslední změna") {
                            Text(latest)
                        }
                    }
                }
            }
            .navigationTitle("Proč tento čas?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { showingTimeExplanation = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var scheduleHistorySheet: some View {
        NavigationStack {
            List(Array(scheduleHistory.reversed()), id: \.self) { entry in
                Text(entry)
            }
            .navigationTitle("Historie přepočtů")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { showingScheduleHistory = false }
                }
            }
        }
    }

    private var liveActivitySettingsSheet: some View {
        NavigationStack {
            Form {
                LiveActivityOptionsView(
                    liveActivityService: liveActivityService,
                    currentStopExists: currentStop != nil,
                    showCurrentStop: $showCurrentStop,
                    showNextStop: $showNextStop,
                    showDepartureTime: $showDepartureTime,
                    showDelay: $showDelay,
                    restart: { startLiveActivity(forceRestart: true) }
                )
            }
            .navigationTitle("Lock Screen a Dynamic Island")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { showingLiveActivityOptions = false }
                }
            }
        }
    }

    private func openCurrentStopInMaps(_ stop: TripStop) {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return }
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        let item = MKMapItem(placemark: placemark)
        item.name = stop.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    private func shareStatusText(for stop: TripStop) -> String {
        switch currentPhase {
        case .atPlace:
            return WaymintLocalization.format("Jsem na místě %@. Plánovaný odchod je v %@.", stop.title, stop.plannedDeparture.waymintTime)
        case .travelingToPlace:
            return WaymintLocalization.format("Mířím na %@. Odhadovaný příjezd je v %@.", stop.title, (gpsETA ?? stop.plannedArrival).waymintTime)
        case nil:
            return WaymintLocalization.format("Právě pokračuji v cestě %@.", trip.title)
        }
    }

    private func openNearbySearch(_ query: String, fallbackStop: TripStop) {
        let coordinate: CLLocationCoordinate2D?
        if let location = locationService.location {
            coordinate = location.coordinate
        } else if let latitude = fallbackStop.latitude, let longitude = fallbackStop.longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }
        guard let coordinate,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://maps.apple.com/?q=\(encodedQuery)&ll=\(coordinate.latitude),\(coordinate.longitude)") else { return }
        UIApplication.shared.open(url)
    }

    private func addQuickPause(minutes: Int, at stop: TripStop) {
        guard trip.status != .paused, let index = currentStopIndex else { return }
        captureUndoSnapshot()
        let interval = TimeInterval(minutes * 60)
        if currentPhase == .atPlace {
            let newDeparture = stop.plannedDeparture.addingTimeInterval(interval)
            stop.plannedDeparture = newDeparture
            scheduleCalculator.recalculateAfterDeparture(
                newDeparture,
                from: index,
                stops: stops,
                segments: trip.sortedTravelSegments
            )
        } else {
            recalculateFromArrival(stop.plannedArrival.addingTimeInterval(interval), at: index)
        }
        recordScheduleChange(WaymintLocalization.format("Přidána pauza %d minut", minutes))
        refreshAfterScheduleChange()
    }

    private func start(_ stop: TripStop) {
        guard trip.status != .paused else { return }
        captureUndoSnapshot()
        gpsRoutePolyline = nil
        stop.status = .active
        let arrival = Date()
        stop.actualStart = stop.actualStart ?? arrival
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            recalculateFromArrival(arrival, at: index)
        }
        refreshAfterScheduleChange()
        updateLiveActivity()
        recordScheduleChange(WaymintLocalization.format("Příchod na %@", stop.title))
    }

    private func complete(_ stop: TripStop) {
        guard trip.status != .paused else { return }
        captureUndoSnapshot()
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
        scheduleNotifications()
        refreshAfterScheduleChange()
        recordScheduleChange(WaymintLocalization.format("Dokončena zastávka %@", stop.title))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                showingCompletionPulse = false
            }
        }
    }

    private func skip(_ stop: TripStop) {
        guard trip.status != .paused else { return }
        captureUndoSnapshot()
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
        scheduleNotifications()
        refreshAfterScheduleChange()
        recordScheduleChange(WaymintLocalization.format("Přeskočena zastávka %@", stop.title))
    }

    private func markNext(after stop: TripStop) {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }),
              stops.indices.contains(index + 1) else {
            trip.status = .completed
            trip.actualEndedAt = .now
            restoreFlexibleStartIfNeeded()
            notificationScheduler.cancelNotifications(for: trip.id)
            locationService.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await liveActivityService.end() }
            showingTripSummary = true
            return
        }
        stops[index + 1].status = .next
    }

    private func stopTrip() {
        trip.status = .stopped
        trip.actualEndedAt = .now
        trip.pausedAt = nil
        trip.updatedAt = .now
        restoreFlexibleStartIfNeeded()
        notificationScheduler.cancelNotifications(for: trip.id)
        locationService.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        recordScheduleChange(WaymintLocalization.text("Cesta zastavena"))
        Task {
            await liveActivityService.end()
            dismiss()
        }
    }

    private func togglePause() {
        if trip.status == .paused {
            let resumedAt = Date()
            let pauseDuration = resumedAt.timeIntervalSince(trip.pausedAt ?? resumedAt)
            trip.accumulatedPauseSeconds += max(0, pauseDuration)
            trip.pausedAt = nil
            trip.status = .active
            if let index = currentStopIndex {
                let anchor = stops[index].plannedArrival.addingTimeInterval(max(0, pauseDuration))
                recalculateFromArrival(anchor, at: index)
            }
            if gpsCorrectionEnabled { locationService.start() }
            scheduleNotifications()
            recordScheduleChange(WaymintLocalization.text("Cesta znovu spuštěna po pauze"))
            startLiveActivity(forceRestart: true)
        } else {
            trip.pausedAt = .now
            trip.status = .paused
            locationService.stop()
            notificationScheduler.cancelNotifications(for: trip.id)
            recordScheduleChange(WaymintLocalization.text("Cesta pozastavena"))
            Task { await liveActivityService.end() }
        }
        trip.updatedAt = .now
        updateLiveActivity()
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

    private func consumePendingVoiceAction() {
        let defaults = UserDefaults.standard
        guard let action = defaults.string(forKey: "waymintPendingVoiceAction") else { return }
        defaults.removeObject(forKey: "waymintPendingVoiceAction")
        consumeVoiceAction(action)
    }

    private func consumeVoiceAction(_ rawValue: String) {
        guard let action = WaymintVoiceAction(rawValue: rawValue), let currentStop else { return }
        switch action {
        case .arrive:
            if currentStop.status == .planned || currentStop.status == .next { start(currentStop) }
        case .complete:
            if currentStop.status == .active { complete(currentStop) }
        case .addBreak:
            addQuickPause(minutes: 10, at: currentStop)
        }
        updateVoiceSnapshot()
    }

    private func updateVoiceSnapshot() {
        let defaults = UserDefaults.standard
        defaults.set(currentStopTitle, forKey: "waymintVoiceCurrentStop")
        if let currentStop {
            defaults.set(phaseSubtitle(for: currentStop), forKey: "waymintVoiceCurrentDetail")
        } else {
            defaults.removeObject(forKey: "waymintVoiceCurrentDetail")
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
        guard notificationsEnabled, trip.status != .paused, trip.status != .stopped, trip.status != .completed else { return }
        Task {
            let result = await notificationScheduler.scheduleTripNotifications(for: trip)
            if !result.isAuthorized {
                notificationsEnabled = false
                gpsCorrectionMessage = WaymintLocalization.text("Oznámení jsou vypnutá v nastavení systému.")
            } else if result.failedCount > 0 {
                gpsCorrectionMessage = WaymintLocalization.format("Část upozornění se nepodařilo naplánovat (%d).", result.failedCount)
            }
        }
    }

    private func recalculateFromArrival(_ arrival: Date, at index: Int) {
        scheduleCalculator.recalculateFromArrival(
            arrival,
            at: index,
            stops: stops,
            segments: trip.sortedTravelSegments
        )
        applyDelayStrategy(from: index)
    }

    private func applyDelayStrategy(from index: Int) {
        switch trip.delayResponseStrategy {
        case .shiftEverything, .preserveReservations:
            break
        case .shortenOptionalStops:
            for stop in stops.dropFirst(index) where !stop.isRequired && !stop.isTimeAnchor {
                let reduction = min(15, max(0, stop.plannedVisitDurationMinutes - 10))
                guard reduction > 0 else { continue }
                stop.plannedVisitDurationMinutes -= reduction
                stop.plannedDeparture = stop.plannedArrival.addingTimeInterval(TimeInterval(stop.plannedVisitDurationMinutes * 60))
            }
            scheduleCalculator.recalculateFromArrival(stops[index].plannedArrival, at: index, stops: stops, segments: trip.sortedTravelSegments)
        case .suggestSkipping:
            if let optional = stops.dropFirst(index).first(where: { !$0.isRequired && !$0.isTimeAnchor }) {
                gpsCorrectionMessage = WaymintLocalization.format("Kvůli zpoždění můžeš zvážit přeskočení: %@.", optional.title)
            }
        }
    }

    private func prepareTripForStart() {
        let previousStatus = trip.status
        let wasStopped = previousStatus == .stopped
        let wasPaused = previousStatus == .paused
        let resumedAt = Date()
        let startedAt = wasStopped ? Date() : (trip.actualStartedAt ?? Date())
        trip.status = .active
        trip.actualStartedAt = startedAt
        trip.actualEndedAt = nil

        if wasPaused, let pausedAt = trip.pausedAt {
            let pauseDuration = max(0, resumedAt.timeIntervalSince(pausedAt))
            trip.accumulatedPauseSeconds += pauseDuration
            if let index = currentStopIndex {
                recalculateFromArrival(stops[index].plannedArrival.addingTimeInterval(pauseDuration), at: index)
            }
            recordScheduleChange(WaymintLocalization.text("Cesta obnovena po restartu"))
        }
        trip.pausedAt = nil

        if wasStopped, let index = currentStopIndex {
            recalculateFromArrival(resumedAt, at: index)
            recordScheduleChange(WaymintLocalization.text("Zastavená cesta znovu spuštěna"))
        }

        guard !trip.hasFixedStartTime else { return }
        trip.hasTemporaryActiveStartTime = true
        trip.hasFixedStartTime = true
        trip.startTime = startedAt
        trip.date = startedAt
        if !wasStopped {
            scheduleCalculator.recalculateTrip(trip, anchor: startedAt)
        }
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
        updateLiveActivity()
    }

    private func correctSchedule(using location: CLLocation) async {
        guard trip.status == .active else { return }
        guard let currentStop else { return }
        guard location.horizontalAccuracy >= 0 else { return }
        guard location.horizontalAccuracy <= 50 else {
            gpsCorrectionMessage = WaymintLocalization.format("GPS signál je zatím příliš nepřesný (±%d m). Čekám na přesnější polohu.", Int(location.horizontalAccuracy))
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
                    gpsCorrectionMessage = WaymintLocalization.format("Na místě · %d m od %@. Čas návštěvy běží.", distance, currentStop.title)
                } else if confirmedInsideStopID == currentStop.id, distance >= gpsDepartureRadius {
                    if let departureCandidateAt,
                       Date().timeIntervalSince(departureCandidateAt) >= Double(gpsDepartureConfirmationSeconds) {
                        gpsCorrectionMessage = WaymintLocalization.format("Waymint rozpoznal odchod z %@.", currentStop.title)
                        captureUndoSnapshot()
                        recordScheduleChange(WaymintLocalization.format("GPS: automaticky zaznamenán odchod z %@, vzdálenost %d m", currentStop.title, distance))
                        confirmedInsideStopID = nil
                        self.departureCandidateAt = nil
                        complete(currentStop)
                    } else if departureCandidateAt == nil {
                        self.departureCandidateAt = .now
                        gpsCorrectionMessage = WaymintLocalization.format("Ověřuji odchod z %@…", currentStop.title)
                    }
                } else {
                    departureCandidateAt = nil
                    gpsCorrectionMessage = WaymintLocalization.format("GPS je aktivní · %d m od %@.", distance, currentStop.title)
                }
            } else {
                gpsCorrectionMessage = WaymintLocalization.text("GPS je aktivní. Aktuální zastávka nemá uložené souřadnice.")
            }
            return
        }

        guard currentStop.status == .next || currentStop.status == .planned,
              let latitude = currentStop.latitude,
              let longitude = currentStop.longitude,
              let index = stops.firstIndex(where: { $0.id == currentStop.id }) else {
            return
        }

        if let gpsRoutePolyline,
           distance(from: location.coordinate, to: gpsRoutePolyline) > 140 {
            gpsCorrectionMessage = WaymintLocalization.text("Jsi mimo poslední trasu. Přepočítávám cestu k další zastávce.")
            lastGPSRouteAttemptAt = nil
            self.gpsRoutePolyline = nil
            recordScheduleChange(WaymintLocalization.text("Odbočení z trasy, vyžádán nový přesun"))
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
            captureUndoSnapshot()
            currentStop.status = .active
            currentStop.actualStart = currentStop.actualStart ?? .now
            confirmedInsideStopID = currentStop.id
            departureCandidateAt = nil
            recalculateFromArrival(.now, at: index)
            gpsETA = .now
            gpsRoutePolyline = nil
            gpsCorrectionMessage = WaymintLocalization.format("Waymint rozpoznal příchod na %@.", currentStop.title)
            recordScheduleChange(WaymintLocalization.format("GPS: automaticky zaznamenán příchod na %@, vzdálenost %d m", currentStop.title, Int(distance)))
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
            captureUndoSnapshot()
            gpsRoutePolyline = route.polyline
            let arrival = Date().addingTimeInterval(route.expectedTravelTime)
            recalculateFromArrival(arrival, at: index)
            gpsETA = arrival
            gpsCorrectionMessage = WaymintLocalization.format("GPS odhad: %d m, příjezd v %@.", Int(route.distance), arrival.waymintTime)
            recordScheduleChange(WaymintLocalization.format("GPS: nový odhad příjezdu na %@ v %@", currentStop.title, arrival.waymintTime))
            lastGPSCorrectionAt = .now
            lastCorrectedLocation = location
            refreshAfterScheduleChange()
        } catch {
            gpsCorrectionMessage = WaymintLocalization.text("GPS funguje, ale Apple Mapy teď nedokázaly spočítat trasu.")
        }
    }

    private var phasePrimaryText: String {
        if trip.hasSuspiciousRunningDuration {
            return "—"
        }
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
            return WaymintLocalization.format("Start: %@", currentStop.title)
        }
        return currentStop.title
    }

    private func phaseSubtitle(for stop: TripStop) -> String {
        guard trip.hasFixedStartTime else {
            switch currentPhase {
            case .atPlace:
                return stop.plannedVisitDurationMinutes > 0
                    ? WaymintLocalization.format("Jsi na místě. Doporučená délka je %@.", stop.plannedVisitDurationMinutes.minutesLabel)
                    : WaymintLocalization.text("Jsi na startu cesty.")
            case .travelingToPlace:
                return WaymintLocalization.text("Pokračuj na další bod bez pevně daného času.")
            case nil:
                return ""
            }
        }
        switch currentPhase {
        case .atPlace:
            let summary = delayCalculator.delay(now: now, plannedTime: stop.plannedDeparture)
            if summary.isDelayed {
                return WaymintLocalization.format("Odchod byl plánovaný v %@. %@", stop.plannedDeparture.waymintTime, summary.message)
            }
            return WaymintLocalization.format("Odchod v %@.", stop.plannedDeparture.waymintTime)
        case .travelingToPlace:
            let summary = delayCalculator.delay(now: now, plannedTime: stop.plannedArrival)
            if summary.isDelayed {
                return WaymintLocalization.format("Příjezd byl plánovaný v %@. %@", stop.plannedArrival.waymintTime, summary.message)
            }
            return WaymintLocalization.format("Příjezd v %@.", stop.plannedArrival.waymintTime)
        case nil:
            return ""
        }
    }

    private func stopTimeSubtitle(for stop: TripStop) -> String {
        if currentPhase == .atPlace {
            return WaymintLocalization.format("Na místě do %@", stop.plannedDeparture.waymintTime)
        }
        return WaymintLocalization.format("Příjezd %@", stop.plannedArrival.waymintTime)
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

    private func captureScheduleSnapshot() {
        lastScheduleSnapshot = ActiveScheduleSnapshot(
            stops: stops.map {
                .init(id: $0.id, arrival: $0.plannedArrival, departure: $0.plannedDeparture, status: $0.status, actualStart: $0.actualStart, actualEnd: $0.actualEnd)
            },
            segments: trip.sortedTravelSegments.map {
                .init(id: $0.id, duration: $0.plannedDurationMinutes, departure: $0.plannedDeparture)
            }
        )
    }

    private func captureUndoSnapshot() {
        captureScheduleSnapshot()
        let expiry = Date().addingTimeInterval(15)
        undoExpiresAt = expiry
        Task {
            try? await Task.sleep(for: .seconds(15))
            if undoExpiresAt == expiry {
                lastScheduleSnapshot = nil
                undoExpiresAt = nil
            }
        }
    }

    private func restoreLastScheduleSnapshot() {
        guard let snapshot = lastScheduleSnapshot else { return }
        for value in snapshot.stops {
            guard let stop = stops.first(where: { $0.id == value.id }) else { continue }
            stop.plannedArrival = value.arrival
            stop.plannedDeparture = value.departure
            stop.status = value.status
            stop.actualStart = value.actualStart
            stop.actualEnd = value.actualEnd
        }
        for value in snapshot.segments {
            guard let segment = trip.sortedTravelSegments.first(where: { $0.id == value.id }) else { continue }
            segment.plannedDurationMinutes = value.duration
            segment.plannedDeparture = value.departure
        }
        lastScheduleSnapshot = nil
        undoExpiresAt = nil
        recordScheduleChange(WaymintLocalization.text("Vrácena poslední GPS změna"))
        refreshAfterScheduleChange()
    }


    private var gpsQuality: GPSQuality {
        guard let location = locationService.location,
              abs(location.timestamp.timeIntervalSinceNow) < 45 else { return .waiting }
        if location.horizontalAccuracy <= 25 { return .precise(Int(location.horizontalAccuracy)) }
        return .weak(Int(location.horizontalAccuracy))
    }

    private func distance(from coordinate: CLLocationCoordinate2D, to polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount > 0 else { return .greatestFiniteMagnitude }
        let target = MKMapPoint(coordinate)
        let points = polyline.points()
        var minimum = CLLocationDistance.greatestFiniteMagnitude
        for index in 0..<polyline.pointCount {
            minimum = min(minimum, target.distance(to: points[index]))
        }
        return minimum
    }
}

private struct ActiveTripCompletionSummary: View {
    @Environment(\.dismiss) private var dismiss
    let trip: TripPlan
    @State private var shareURL: URL?
    @State private var showingShare = false

    private var completed: Int { trip.sortedStops.filter { $0.status == .completed }.count }
    private var skipped: Int { trip.sortedStops.filter { $0.status == .skipped }.count }
    private var deviation: Int {
        guard let actual = trip.actualDurationMinutes else { return 0 }
        return actual - trip.approximateDurationMinutes
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(WaymintTheme.primaryGreen)
                Text("Cesta dokončena").font(.largeTitle.bold())
                HStack(spacing: 12) {
                    summary("Skutečný čas", trip.actualDurationMinutes?.minutesLabel ?? "–")
                    summary("Navštíveno", "\(completed)")
                    summary("Přeskočeno", "\(skipped)")
                }
                summary("Odchylka od plánu", deviation == 0 ? "Bez odchylky" : "\(deviation > 0 ? "+" : "")\(deviation) min")
                Button {
                    Task {
                        shareURL = try? await InstagramTripCardService().create(for: trip, style: .light, excludedStopIDs: [])
                        showingShare = shareURL != nil
                    }
                } label: {
                    Label("Sdílet souhrn", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("Souhrn")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { dismiss() } } }
            .sheet(isPresented: $showingShare) {
                if let shareURL { ShareSheet(activityItems: [shareURL]) }
            }
        }
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.headline).foregroundStyle(WaymintTheme.darkGreen)
            Text(title).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private enum GPSQuality {
    case precise(Int)
    case weak(Int)
    case waiting

    var label: String {
        switch self {
        case .precise(let meters): return WaymintLocalization.format("Přesná · ±%d m", meters)
        case .weak(let meters): return WaymintLocalization.format("Slabá · ±%d m", meters)
        case .waiting: return WaymintLocalization.text("Čekám na polohu")
        }
    }

    var systemImage: String {
        switch self {
        case .precise: "location.fill"
        case .weak: "location.circle"
        case .waiting: "location.slash"
        }
    }

    var color: Color {
        switch self {
        case .precise: WaymintTheme.success
        case .weak: WaymintTheme.warning
        case .waiting: WaymintTheme.secondaryText
        }
    }
}

private struct ActiveScheduleSnapshot {
    struct StopValue {
        let id: UUID
        let arrival: Date
        let departure: Date
        let status: StopStatus
        let actualStart: Date?
        let actualEnd: Date?
    }

    struct SegmentValue {
        let id: UUID
        let duration: Int
        let departure: Date?
    }

    let stops: [StopValue]
    let segments: [SegmentValue]
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
    let plannedRouteLines: [TripMapRouteLine]
    @State private var position: MapCameraPosition = .automatic
    @State private var didCenterOnUser = false

    var body: some View {
        Map(position: $position) {
            ForEach(plannedRouteLines) { routeLine in
                MapPolyline(routeLine.polyline)
                    .stroke(
                        WaymintTheme.primaryGreen.opacity(routePolyline == nil ? 0.82 : 0.38),
                        style: StrokeStyle(
                            lineWidth: routePolyline == nil ? 6 : 4,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: routeLine.isEstimated ? [8, 7] : []
                        )
                    )
            }
            if let routePolyline {
                MapPolyline(routePolyline)
                    .stroke(
                        WaymintTheme.darkGreen,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
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
            guard let location, !didCenterOnUser else { return }
            position = .region(region(centeredOn: location.coordinate))
            didCenterOnUser = true
        }
        .onChange(of: currentStop?.id) { _, _ in
            guard let userLocation else {
                didCenterOnUser = false
                return
            }
            position = .region(region(centeredOn: userLocation.coordinate))
            didCenterOnUser = true
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
                    Label(WaymintLocalization.format("±%d m", Int(userLocation.horizontalAccuracy)), systemImage: "scope")
                } else {
                    Label("Čekám na polohu", systemImage: "location.slash")
                }
                if let gpsETA {
                    Label(WaymintLocalization.format("Příjezd %@", gpsETA.waymintTime), systemImage: "clock")
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
                    Label {
                        Text(LocalizedStringKey(liveActivityService.activityID == nil ? "Spustit" : "Restartovat"))
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
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
                return WaymintLocalization.format("Další bod · na místě %@", stop.plannedVisitDurationMinutes.minutesLabel)
            }
            return stop.plannedVisitDurationMinutes > 0
                ? WaymintLocalization.format("Na místě %@", stop.plannedVisitDurationMinutes.minutesLabel)
                : WaymintLocalization.text("Start cesty")
        }
        if isTravelingToStop {
            return WaymintLocalization.format("Příjezd %@ · potom na místě %@", stop.plannedArrival.waymintTime, stop.plannedVisitDurationMinutes.minutesLabel)
        }
        return WaymintLocalization.format("Na místě do %@", stop.plannedDeparture.waymintTime)
    }

    private var remainingText: String {
        guard showsClockTimes else {
            return WaymintLocalization.text(isTravelingToStop ? "Čas se počítá od spuštění cesty." : "Cesta běží bez pevného odchodu.")
        }
        if isTravelingToStop {
            return WaymintLocalization.format("Do příjezdu zbývá %@.", minutesUntil(stop.plannedArrival).minutesLabel)
        }
        return WaymintLocalization.format("Do odchodu zbývá %@.", minutesUntil(stop.plannedDeparture).minutesLabel)
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
                Text(LocalizedStringKey(title))
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
