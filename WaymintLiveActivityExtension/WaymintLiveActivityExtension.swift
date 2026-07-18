import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WaymintLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        WaymintHomeWidget()
        WaymintTripLiveActivity()
    }
}

struct WaymintHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaymintHomeWidget", provider: WaymintHomeTimelineProvider()) { entry in
            WaymintHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Waymint")
        .description("Rychly prehled aktivni cesty.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WaymintHomeEntry: TimelineEntry {
    let date: Date
}

private struct WaymintHomeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaymintHomeEntry {
        WaymintHomeEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WaymintHomeEntry) -> Void) {
        completion(WaymintHomeEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaymintHomeEntry>) -> Void) {
        completion(Timeline(entries: [WaymintHomeEntry(date: .now)], policy: .never))
    }
}

private struct WaymintHomeWidgetView: View {
    let entry: WaymintHomeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(Color(red: 0.16, green: 0.45, blue: 0.31))

            Text("Waymint")
                .font(.headline)

            Text("Spust aktivni cestu v aplikaci.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(Color(.systemBackground), for: .widget)
    }
}

struct WaymintTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WaymintTripActivityAttributes.self) { context in
            LiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.08, green: 0.23, blue: 0.17))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedWaymintBrand()
                        .padding(.leading, 10)
                }

                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandStopTitle(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandTimePill(context: context)
                        .padding(.trailing, 10)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 7) {
                        HStack(spacing: 8) {
                            if context.state.showDelay {
                                DelayBadge(minutes: context.state.delayMinutes, compact: true)
                                    .frame(maxWidth: 118)
                            }

                            if context.state.showNextStop, let nextStopName = context.state.nextStopName {
                                Label(nextStopName.activityTitle, systemImage: "arrow.right")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.74))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .frame(maxWidth: 142)
                            }
                        }

                        DynamicIslandControls(tripID: context.attributes.tripID)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 1)
                }
            } compactLeading: {
                CompactWaymintMark(phaseTitle: context.state.phaseTitle)
            } compactTrailing: {
                CompactCountdown(targetDate: context.state.targetDate)
            } minimal: {
                CompactWaymintMark(phaseTitle: context.state.phaseTitle, minimal: true)
            }
            .widgetURL(URL(string: "waymint://active-trip/\(context.attributes.tripID.uuidString)"))
            .keylineTint(Color(red: 0.16, green: 0.45, blue: 0.31))
        }
    }
}

private struct ExpandedWaymintBrand: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("W")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.56, green: 0.95, blue: 0.70))
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: 42, height: 27)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.42, blue: 0.28), Color(red: 0.06, green: 0.25, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay { Capsule().stroke(.white.opacity(0.13), lineWidth: 0.7) }
            .accessibilityLabel("Waymint")
    }
}

private struct CompactWaymintMark: View {
    let phaseTitle: String
    var minimal = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.26, green: 0.72, blue: 0.48), Color(red: 0.08, green: 0.32, blue: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("W")
                .font(.system(size: minimal ? 10 : 9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Circle()
                .stroke(Color(red: 0.56, green: 0.95, blue: 0.70).opacity(0.72), lineWidth: 1)
        }
        .frame(width: minimal ? 22 : 20, height: minimal ? 22 : 20)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: phaseTitle == "Na místě" ? "circle.fill" : "arrow.up.right")
                .font(.system(size: 5, weight: .black))
                .foregroundStyle(Color(red: 0.56, green: 0.95, blue: 0.70))
                .padding(2)
                .background(.black, in: Circle())
                .offset(x: 2, y: 2)
        }
        .padding(.leading, minimal ? 0 : 2)
        .accessibilityLabel("Waymint · \(phaseTitle)")
    }
}

private struct CompactCountdown: View {
    let targetDate: Date

    var body: some View {
        Text(timerInterval: Date()...max(targetDate, Date()), countsDown: true)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(red: 0.70, green: 1.0, blue: 0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.trailing, 3)
            .contentTransition(.numericText(countsDown: true))
    }
}

private struct DynamicIslandControls: View {
    let tripID: UUID

    var body: some View {
        HStack(spacing: 7) {
            DynamicIslandControlLink(
                title: "Start",
                systemImage: "play.fill",
                tint: Color(red: 0.56, green: 0.95, blue: 0.70),
                url: controlURL("start")
            )
            DynamicIslandControlLink(
                title: "Hotovo",
                systemImage: "checkmark",
                tint: Color(red: 0.56, green: 0.95, blue: 0.70),
                url: controlURL("complete")
            )
            DynamicIslandControlLink(
                title: "Přeskočit",
                systemImage: "forward.fill",
                tint: Color(red: 1.0, green: 0.72, blue: 0.38),
                url: controlURL("skip")
            )
        }
        .frame(maxWidth: 245)
    }

    private func controlURL(_ action: String) -> URL {
        URL(string: "waymint://active-trip/\(tripID.uuidString)?action=\(action)")!
    }
}

private struct DynamicIslandControlLink: View {
    let title: String
    let systemImage: String
    let tint: Color
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .frame(height: 25)
                .padding(.horizontal, 5)
                .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct DynamicIslandStopTitle: View {
    let context: ActivityViewContext<WaymintTripActivityAttributes>

    var body: some View {
        VStack(spacing: 2) {
            Text(context.state.phaseTitle.uppercased())
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color(red: 0.46, green: 0.9, blue: 0.66))
                .lineLimit(1)

            Text(context.state.showCurrentStop ? context.state.currentStopName.activityTitle : context.attributes.tripTitle.activityTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 118)
        }
        .frame(maxWidth: 126)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DynamicIslandTimePill: View {
    let context: ActivityViewContext<WaymintTripActivityAttributes>

    var body: some View {
        VStack(spacing: 1) {
            Text(timerInterval: Date()...max(context.state.targetDate, Date()), countsDown: true)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if context.state.showDepartureTime, let plannedDeparture = context.state.plannedDeparture {
                Text(plannedDeparture, style: .time)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .frame(width: 44, height: 28)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompactPhaseIcon: View {
    let phaseTitle: String

    var body: some View {
        Image(systemName: phaseTitle == "Na místě" ? "timer" : "arrow.triangle.turn.up.right.diamond.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(red: 0.46, green: 0.9, blue: 0.66))
            .frame(width: 18, height: 18)
            .background(Color(red: 0.16, green: 0.45, blue: 0.31).opacity(0.35), in: Circle())
    }
}

private struct LiveActivityLockScreenView: View {
    let context: ActivityViewContext<WaymintTripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LockScreenHeader(context: context)

            HStack(alignment: .center, spacing: 14) {
                LockScreenPhaseMark(phaseTitle: context.state.phaseTitle)

                VStack(alignment: .leading, spacing: 5) {
                    Text(context.state.phaseTitle.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Color(red: 0.56, green: 0.95, blue: 0.70))
                        .lineLimit(1)

                    Text(context.state.showCurrentStop ? context.state.currentStopName : context.attributes.tripTitle)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                LockScreenTimeBlock(context: context)
            }

            HStack(spacing: 8) {
                if context.state.showNextStop, let nextStopName = context.state.nextStopName {
                    LockScreenInfoChip(
                        title: "Následuje",
                        value: nextStopName,
                        systemImage: "arrow.right"
                    )
                }

                if context.state.showDelay {
                    LockScreenDelayChip(minutes: context.state.delayMinutes)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.18, blue: 0.13),
                        Color(red: 0.08, green: 0.27, blue: 0.19),
                        Color(red: 0.04, green: 0.10, blue: 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.52, green: 0.96, blue: 0.66).opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 170
                )
            }
        )
        .foregroundStyle(.white)
    }
}

private struct LockScreenHeader: View {
    let context: ActivityViewContext<WaymintTripActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            ExpandedWaymintBrand()

            Text(context.attributes.tripTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Spacer()

            Image(systemName: "map.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct LockScreenPhaseMark: View {
    let phaseTitle: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(.white.opacity(0.13))
                .frame(width: 54, height: 54)

            Image(systemName: phaseTitle == "Na místě" ? "timer" : "arrow.triangle.turn.up.right.diamond.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Color(red: 0.56, green: 0.95, blue: 0.70))
        }
    }
}

private struct LockScreenTimeBlock: View {
    let context: ActivityViewContext<WaymintTripActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(timerInterval: Date()...max(context.state.targetDate, Date()), countsDown: true)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if context.state.showDepartureTime, let plannedDeparture = context.state.plannedDeparture {
                Label {
                    Text(plannedDeparture, style: .time)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
            }
        }
        .frame(minWidth: 58, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LockScreenInfoChip: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.54))
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color(red: 0.56, green: 0.95, blue: 0.70))
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct LockScreenDelayChip: View {
    let minutes: Int

    var body: some View {
        Label(delayText, systemImage: minutes > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(minutes > 0 ? Color(red: 1, green: 0.78, blue: 0.42) : Color(red: 0.56, green: 0.95, blue: 0.70))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 13))
    }

    private var delayText: String {
        if minutes > 0 {
            return "+\(abs(minutes).compactMinutesText)"
        }
        if minutes < 0 {
            return "-\(abs(minutes).compactMinutesText)"
        }
        return "Včas"
    }
}

private struct DelayBadge: View {
    let minutes: Int
    var compact = false

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, compact ? 8 : 8)
            .padding(.vertical, compact ? 3 : 5)
            .background(background.opacity(0.22), in: Capsule())
    }

    private var text: String {
        let absoluteMinutes = abs(minutes)
        let timeText: String
        if compact, absoluteMinutes >= 60 {
            let hours = absoluteMinutes / 60
            let remainingMinutes = absoluteMinutes % 60
            timeText = remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        } else if absoluteMinutes >= 60 {
            let hours = absoluteMinutes / 60
            let remainingMinutes = absoluteMinutes % 60
            timeText = remainingMinutes == 0 ? "\(hours) h" : "\(hours) h \(remainingMinutes) min"
        } else {
            timeText = "\(absoluteMinutes) min"
        }

        if minutes > 0 {
            return compact ? "+\(timeText)" : "\(timeText) zpoždění"
        }
        if minutes < 0 {
            return compact ? "-\(timeText)" : "\(timeText) napřed"
        }
        return compact ? "Včas" : "Podle plánu"
    }

    private var icon: String {
        minutes > 0 ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var background: Color {
        minutes > 0 ? .orange : .green
    }
}

private extension String {
    var activityTitle: String {
        if count <= 14 { return self }
        return String(prefix(13)) + "…"
    }
}

private extension Int {
    var compactMinutesText: String {
        if self >= 60 {
            let hours = self / 60
            let minutes = self % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)"
        }
        return "\(self)m"
    }
}
