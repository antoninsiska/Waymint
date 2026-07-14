import SwiftUI

struct WaymintOnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    WaymintTheme.lightGreen.opacity(0.56),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    OnboardingLogoMark()
                    Spacer()
                    Button("Přeskočit", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? WaymintTheme.primaryGreen : WaymintTheme.secondaryText.opacity(0.24))
                            .frame(width: index == page ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: page)
                    }
                }

                Button {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            page += 1
                        }
                    }
                } label: {
                    Label(page == pages.count - 1 ? "Začít plánovat" : "Pokračovat", systemImage: page == pages.count - 1 ? "checkmark.circle.fill" : "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)

            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(WaymintTheme.surface)
                    .shadow(color: .black.opacity(0.10), radius: 26, x: 0, y: 16)

                VStack(spacing: 20) {
                    Image(systemName: page.systemImage)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(WaymintTheme.primaryGreen)
                        .frame(width: 86, height: 86)
                        .background(WaymintTheme.lightGreen, in: RoundedRectangle(cornerRadius: 24))

                    VStack(spacing: 10) {
                        Text(page.title)
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(WaymintTheme.primaryText)
                            .multilineTextAlignment(.center)

                        Text(page.message)
                            .font(.body)
                            .foregroundStyle(WaymintTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.points, id: \.title) { point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: point.systemImage)
                                    .font(.headline)
                                    .foregroundStyle(WaymintTheme.primaryGreen)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(WaymintTheme.primaryText)
                                    Text(point.message)
                                        .font(.caption)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(22)
            }
            .frame(maxWidth: 460)

            Spacer(minLength: 8)
        }
    }
}

private struct OnboardingLogoMark: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("WM")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(WaymintTheme.primaryGreen, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text("Waymint")
                    .font(.headline.weight(.bold))
                Text("Průvodce")
                    .font(.caption)
                    .foregroundStyle(WaymintTheme.secondaryText)
            }
        }
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let message: String
    let points: [OnboardingPoint]

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "flag.checkered",
            title: "První bod je start",
            message: "Cestu začni místem, odkud vyrážíš. Waymint z něj pak počítá přesuny k dalším zastávkám.",
            points: [
                OnboardingPoint(systemImage: "1.circle.fill", title: "Číslo v timeline", message: "Ukazuje pořadí bodu v cestě. Jednička je vždy start."),
                OnboardingPoint(systemImage: "plus", title: "Přidání bodu", message: "Tlačítkem plus přidáš další místo, přesun nebo zastávku.")
            ]
        ),
        OnboardingPage(
            systemImage: "arrow.triangle.turn.up.right.diamond.fill",
            title: "Dojezd a čas na místě",
            message: "Mezi body vidíš dojezd tam. Po příjezdu se aktivní cesta přepne na čas, který máš na místě.",
            points: [
                OnboardingPoint(systemImage: "tram.fill", title: "Dojezd tam", message: "Ukazuje dopravu, délku přesunu a rezervu."),
                OnboardingPoint(systemImage: "timer", title: "Čas na místě", message: "Po příjezdu sleduje, kolik zbývá do odchodu.")
            ]
        ),
        OnboardingPage(
            systemImage: "ticket.fill",
            title: "Vstupenky jsou u místa",
            message: "PDF, obrázek, QR kód nebo odkaz můžeš připnout k zastávce a otevřít ho přímo z detailu.",
            points: [
                OnboardingPoint(systemImage: "qrcode", title: "QR a obrázky", message: "Zobrazí se přímo v aplikaci jako velký náhled."),
                OnboardingPoint(systemImage: "bell.badge", title: "Upozornění", message: "Waymint může připomenout odchod nebo vstupenky poblíž místa.")
            ]
        ),
        OnboardingPage(
            systemImage: "lock.fill",
            title: "Lock Screen a Dynamic Island",
            message: "Při spuštěné cestě uvidíš nejbližší stav i mimo aplikaci. Ukazuje dojezd, čas na místě a případné zpoždění.",
            points: [
                OnboardingPoint(systemImage: "iphone", title: "Dynamic Island", message: "V popředí aplikace není vidět. Zobrazí se po návratu na plochu nebo na zamčené obrazovce."),
                OnboardingPoint(systemImage: "gearshape", title: "Nastavení", message: "V nastavení můžeš zapnout upozornění a upravit Live Activity.")
            ]
        )
    ]
}

private struct OnboardingPoint {
    let systemImage: String
    let title: String
    let message: String
}
