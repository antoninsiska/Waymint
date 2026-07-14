import Foundation

extension Date {
    var waymintTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var waymintDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension Int {
    var minutesLabel: String {
        if self == 1 {
            return "1 min"
        }
        return "\(self) min"
    }
}

