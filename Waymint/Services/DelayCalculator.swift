import Foundation

struct DelaySummary: Equatable {
    let minutes: Int

    var isDelayed: Bool { minutes > 0 }
    var isAhead: Bool { minutes < 0 }

    var message: String {
        if minutes > 0 {
            return "Jsi \(minutes) min ve zpozdeni."
        }
        if minutes < 0 {
            return "Jsi \(abs(minutes)) min napred."
        }
        return "Jedes presne podle planu."
    }
}

struct DelayCalculator {
    func delay(now: Date, plannedTime: Date) -> DelaySummary {
        let minutes = Int(now.timeIntervalSince(plannedTime) / 60)
        return DelaySummary(minutes: minutes)
    }

    func departureDelay(actualDeparture: Date, plannedDeparture: Date) -> DelaySummary {
        delay(now: actualDeparture, plannedTime: plannedDeparture)
    }

    func suggestedActions(for stop: TripStop, delay: DelaySummary) -> [String] {
        guard delay.isDelayed else {
            return ["Pokracovat podle planu"]
        }

        var actions = ["Zkratit aktualni zastavku", "Posunout nasledujici zastavky", "Pokracovat bez zmeny"]
        if !stop.isRequired {
            actions.insert("Preskocit volitelnou zastavku", at: 1)
        }
        return actions
    }
}

