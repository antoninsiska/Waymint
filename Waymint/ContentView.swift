import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Query private var trips: [TripPlan]
    @AppStorage("waymintHasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showsStarter = true
    @State private var deepLinkedActiveTrip: TripPlan?

    var body: some View {
        ZStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    IPadPlanningRootView()
                } else {
                    CitiesOverviewView()
                }
            }
            .tint(WaymintTheme.primaryGreen)

            if showsStarter {
                WaymintStarterScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeInOut(duration: 0.42)) {
                showsStarter = false
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !hasSeenOnboarding && !showsStarter },
                set: { if !$0 { hasSeenOnboarding = true } }
            )
        ) {
            WaymintOnboardingView {
                hasSeenOnboarding = true
            }
        }
        .fullScreenCover(item: $deepLinkedActiveTrip) { trip in
            NavigationStack {
                ActiveTripView(trip: trip)
            }
        }
        .onOpenURL(perform: handleDeepLink)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "waymint",
              url.host == "active-trip",
              let idText = url.pathComponents.dropFirst().first,
              let tripID = UUID(uuidString: idText),
              let trip = trips.first(where: { $0.id == tripID }) else {
            return
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let action = components.queryItems?.first(where: { $0.name == "action" })?.value {
            UserDefaults.standard.set(action, forKey: "waymintPendingLiveActivityAction")
            UserDefaults.standard.set(tripID.uuidString, forKey: "waymintPendingLiveActivityTripID")
        }
        deepLinkedActiveTrip = trip
    }
}

private struct WaymintStarterScreen: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    WaymintTheme.lightGreen.opacity(0.72),
                    WaymintTheme.primaryGreen.opacity(0.22)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                WaymintLogoMark(size: 104)

                VStack(spacing: 7) {
                    Text("Waymint")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(WaymintTheme.primaryText)

                    Text("Cesty, místa a vstupenky v klidném plánu.")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(WaymintTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            }
            .padding(.bottom, 36)
        }
    }
}

private struct WaymintLogoMark: View {
    let size: CGFloat

    var body: some View {
        Image("WaymintLogo")
            .resizable()
            .scaledToFill()
            .scaleEffect(1.08)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: WaymintTheme.primaryGreen.opacity(0.32), radius: 24, x: 0, y: 16)
            .accessibilityLabel("Waymint")
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container())
}
