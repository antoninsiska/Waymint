import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("waymintHasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showsStarter = true

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
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(
                    LinearGradient(
                        colors: [WaymintTheme.darkGreen, WaymintTheme.primaryGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: WaymintTheme.primaryGreen.opacity(0.32), radius: 24, x: 0, y: 16)

            Text("WM")
                .font(.system(size: size * 0.32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)

            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .offset(y: size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Waymint")
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container())
}
