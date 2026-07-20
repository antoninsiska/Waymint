import Foundation

struct DelaySummary: Equatable {
    let minutes: Int

    var isDelayed: Bool { minutes > 0 }
    var isAhead: Bool { minutes < 0 }

    var message: String {
        if minutes > 0 {
            return WaymintLocalization.format("Jsi %d min ve zpoždění.", minutes)
        }
        if minutes < 0 {
            return WaymintLocalization.format("Jsi %d min napřed.", abs(minutes))
        }
        return WaymintLocalization.text("Jedeš přesně podle plánu.")
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
            return ["Pokračovat podle plánu"]
        }

        var actions = ["Zkrátit aktuální zastávku", "Posunout následující zastávky", "Pokračovat bez změny"]
        if !stop.isRequired {
            actions.insert("Přeskočit volitelnou zastávku", at: 1)
        }
        return actions
    }
}
