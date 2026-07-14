import Combine
import SwiftData
import SwiftUI

struct ActiveTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: TripPlan

    @State private var now = Date()
    @StateObject private var liveActivityService = LiveActivityService()
    @State private var completedStopTitle: String?
    @State private var showingCompletionPulse = false
    @State private var showingLiveActivityOptions = false
    @AppStorage("activeTripShowCurrentStop") private var showCurrentStop = true
    @AppStorage("activeTripShowNextStop") private var showNextStop = true
    @AppStorage("activeTripShowDepartureTime") private var showDepartureTime = true
    @AppStorage("activeTripShowDelay") private var showDelay = true
    @AppStorage("waymintNotificationsEnabled") private var notificationsEnabled = true

    private let delayCalculator = DelayCalculator()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(phasePrimaryText)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(WaymintTheme.darkGreen)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Spacer()
                        StatusPill(phasePillText, systemImage: phasePillIcon)
                    }

                    if let currentStop {
                        Text(currentStopTitle)
                            .font(.title2.weight(.semibold))
                        Text(phaseSubtitle(for: currentStop))
                            .foregroundStyle(phaseSubtitleColor(for: currentStop))
                    } else {
                        Text("Plán nemá žádnou další zastávku.")
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }
                .padding(16)
                .background(WaymintTheme.lightGreen.opacity(0.45), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))

                if let currentStop {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Aktuální zastávka")
                            .font(.headline)
                        ActiveStopSummary(stop: currentStop, showsClockTimes: trip.hasFixedStartTime)

                        HStack(spacing: 8) {
                            ActiveTripActionButton(startActionTitle(for: currentStop), systemImage: startActionIcon(for: currentStop), tint: WaymintTheme.primaryGreen) {
                                start(currentStop)
                            }

                            ActiveTripActionButton("Hotovo", systemImage: "checkmark.circle.fill", tint: WaymintTheme.success) {
                                complete(currentStop)
                            }

                            ActiveTripActionButton("Preskocit", systemImage: "forward.circle.fill", tint: WaymintTheme.warning) {
                                skip(currentStop)
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

                if let currentStop {
                    ActiveStopNotesChecklist(stop: currentStop)
                }

                DisclosureGroup(isExpanded: $showingLiveActivityOptions) {
                    LiveActivityOptionsView(
                        liveActivityService: liveActivityService,
                        currentStopExists: currentStop != nil,
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
                .padding(16)
                .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))

                if let nextStop {
                    Text("Následuje")
                        .font(.headline)
                    ActiveStopSummary(stop: nextStop, showsClockTimes: trip.hasFixedStartTime)
                        .padding(16)
                        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                }

                if let currentStop {
                    let summary = delayCalculator.delay(now: now, plannedTime: currentStop.plannedArrival)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Návrhy při zpoždění")
                            .font(.headline)
                        ForEach(delayCalculator.suggestedActions(for: currentStop, delay: summary), id: \.self) { action in
                            Label(action, systemImage: "lightbulb")
                        }
                    }
                    .padding(16)
                    .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                }
            }
            .padding()
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
            trip.status = .active
            trip.actualStartedAt = trip.actualStartedAt ?? .now
            trip.actualEndedAt = nil
            if stops.allSatisfy({ $0.status == .planned }), let first = stops.first {
                first.status = .active
                first.actualStart = first.actualStart ?? .now
            }
            liveActivityService.refreshStatus()
            startLiveActivity()
            scheduleNotifications()
        }
        .onChange(of: showCurrentStop) { _, _ in updateLiveActivity() }
        .onChange(of: showNextStop) { _, _ in updateLiveActivity() }
        .onChange(of: showDepartureTime) { _, _ in updateLiveActivity() }
        .onChange(of: showDelay) { _, _ in updateLiveActivity() }
        .onReceive(timer) { date in
            now = date
            autoSwitchArrivedStop()
        }
    }

    private func start(_ stop: TripStop) {
        stop.status = .active
        stop.actualStart = stop.actualStart ?? .now
        updateLiveActivity()
    }

    private func complete(_ stop: TripStop) {
        completedStopTitle = stop.title
        withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) {
            showingCompletionPulse = true
        }
        stop.status = .completed
        stop.actualEnd = .now
        markNext(after: stop)
        updateLiveActivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                showingCompletionPulse = false
            }
        }
    }

    private func skip(_ stop: TripStop) {
        stop.status = .skipped
        stop.actualEnd = .now
        markNext(after: stop)
        updateLiveActivity()
    }

    private func markNext(after stop: TripStop) {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }),
              stops.indices.contains(index + 1) else {
            trip.status = .completed
            trip.actualEndedAt = .now
            return
        }
        stops[index + 1].status = .next
    }

    private func autoSwitchArrivedStop() {
        guard trip.hasFixedStartTime else { return }
        guard let currentStop,
              currentStop.status == .next || currentStop.status == .planned,
              now >= currentStop.plannedArrival else {
            return
        }
        currentStop.status = .active
        currentStop.actualStart = currentStop.actualStart ?? now
        updateLiveActivity()
    }

    private func endTrip() {
        trip.status = .completed
        trip.actualEndedAt = .now
        Task {
            await liveActivityService.end()
            dismiss()
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
}

private enum ActiveTripPhase {
    case travelingToPlace
    case atPlace
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
