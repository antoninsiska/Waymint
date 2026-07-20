import Foundation

extension Date {
    var waymintTime: String {
        formatted(.dateTime.hour().minute().locale(WaymintLocalization.currentLocale))
    }

    var waymintDate: String {
        formatted(.dateTime.day().month(.abbreviated).year().locale(WaymintLocalization.currentLocale))
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
