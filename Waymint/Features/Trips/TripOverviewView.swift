import SwiftUI

/// A calm read-only landing page between the city list and the full planner.
/// Editing and timeline management intentionally live one level deeper.
struct TripOverviewView: View {
    @Bindable var trip: TripPlan

    @State private var showingPlanner = false
    @State private var showingActiveTrip = false
    @State private var showingReadiness = false
    @State private var showingStartTimingDecision = false
    @State private var showingTripAssistant = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tripHero

                Button {
                    showingTripAssistant = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: readinessIcon)
                            .font(.title3)
                            .foregroundStyle(readinessColor)
                            .frame(width: 38, height: 38)
                            .background(readinessColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(readinessTitle)
                                .font(.headline)
                                .foregroundStyle(WaymintTheme.primaryText)
                            Text(readinessDetail)
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    .padding(14)
                    .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(readinessColor.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    overviewMetric("\(trip.stopCount)", caption: "Zastávky", icon: "mappin.and.ellipse")
                    overviewMetric("\(trip.totalTicketCount)", caption: "Vstupenky", icon: "ticket")
                    overviewMetric(trip.offlinePreparedAt == nil ? "—" : "✓", caption: "Offline", icon: "arrow.down.circle")
                }

                if let first = trip.sortedStops.first, let last = trip.sortedStops.last {
                    routePreview(first: first, last: last)
                }

                if !trip.landingTitle.isEmpty || !trip.landingSubtitle.isEmpty || !trip.note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("O cestě", systemImage: "text.alignleft")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WaymintTheme.primaryGreen)
                        if !trip.landingTitle.isEmpty {
                            Text(trip.landingTitle).font(.headline)
                        }
                        if !trip.landingSubtitle.isEmpty {
                            Text(trip.landingSubtitle).foregroundStyle(WaymintTheme.secondaryText)
                        }
                        if !trip.note.isEmpty {
                            Text(trip.note).font(.subheadline).foregroundStyle(WaymintTheme.secondaryText)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }

                VStack(spacing: 10) {
                    if trip.status != .completed {
                        Button {
                            requestTripStart()
                        } label: {
                            Label(trip.status == .active || trip.status == .paused ? "Pokračovat v cestě" : "Spustit cestu", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WaymintTheme.primaryGreen)
                    }

                    Button {
                        showingPlanner = true
                    } label: {
                        Label("Otevřít plán", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(WaymintTheme.primaryGreen)
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(WaymintTheme.elevatedSurface.ignoresSafeArea())
        .navigationTitle("Přehled cesty")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingPlanner) {
            TripPlanDetailView(trip: trip)
        }
        .navigationDestination(isPresented: $showingActiveTrip) {
            ActiveTripView(trip: trip)
        }
        .sheet(isPresented: $showingReadiness) {
            TripReadinessView(trip: trip) {
                showingReadiness = false
                showingActiveTrip = true
            }
        }
        .sheet(isPresented: $showingTripAssistant) {
            TripAssistantView(trip: trip)
        }
        .confirmationDialog("Plánovaný čas nesouhlasí", isPresented: $showingStartTimingDecision, titleVisibility: .visible) {
            Button("Přesunout plán na teď") {
                TripStartTimingService().movePlanToNow(trip)
                continueTripStart()
            }
            Button("Spustit podle původního plánu") {
                continueTripStart()
            }
            Button("Zpět do plánování") {
                showingPlanner = true
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text(startTimingWarning)
        }
    }

    private var tripHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(trip.date.waymintDate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                Spacer()
                Label {
                    Text(LocalizedStringKey(trip.status.title))
                } icon: {
                    Image(systemName: "flag.fill")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.14), in: Capsule())
            }

            Text(trip.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            Label(trip.scheduleLabel, systemImage: "clock.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .bottomLeading)
        .background(
            LinearGradient(
                colors: [WaymintTheme.primaryGreen, WaymintTheme.darkGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 92))
                .foregroundStyle(.white.opacity(0.055))
                .padding(18)
        }
        .shadow(color: WaymintTheme.darkGreen.opacity(0.18), radius: 18, y: 8)
    }

    private func overviewMetric(_ value: String, caption: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(WaymintTheme.primaryGreen)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(WaymintTheme.primaryText)
                .lineLimit(1)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WaymintTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func routePreview(first: TripStop, last: TripStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trasa")
                .font(.caption.weight(.bold))
                .foregroundStyle(WaymintTheme.secondaryText)
            HStack(spacing: 12) {
                routePoint(first, systemImage: "flag.fill")
                Rectangle()
                    .fill(WaymintTheme.lightGreen)
                    .frame(height: 2)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WaymintTheme.primaryGreen)
                            .padding(5)
                            .background(WaymintTheme.surface, in: Circle())
                    }
                routePoint(last, systemImage: "flag.checkered")
            }
        }
        .padding(16)
        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func routePoint(_ stop: TripStop, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(WaymintTheme.primaryGreen)
            Text(stop.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WaymintTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 120)
    }

    private var readinessIssues: [TripReadinessIssue] {
        TripReadinessChecker.issues(for: trip)
    }

    private var readinessTitle: String {
        readinessIssues.first?.title ?? WaymintLocalization.text("Cesta je připravená")
    }

    private var readinessDetail: String {
        if let detail = readinessIssues.first?.detail { return detail }
        return WaymintLocalization.text("Klepnutím otevřeš asistenta a možnosti přípravy.")
    }

    private var readinessIcon: String {
        readinessIssues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var readinessColor: Color {
        readinessIssues.isEmpty ? WaymintTheme.success : WaymintTheme.warning
    }

    private func requestTripStart() {
        if TripStartTimingService().needsConfirmation(for: trip) {
            showingStartTimingDecision = true
        } else {
            continueTripStart()
        }
    }

    private func continueTripStart() {
        if TripReadinessChecker.issues(for: trip).isEmpty {
            showingActiveTrip = true
        } else {
            showingReadiness = true
        }
    }

    private var startTimingWarning: String {
        let planned = TripStartTimingService().plannedStart(for: trip)
        return WaymintLocalization.format("Cesta je naplánovaná na %@ v %@, ale teď je %@ v %@. Jak ji chceš spustit?", trip.date.waymintDate, planned.waymintTime, Date().waymintDate, Date().waymintTime)
    }
}
