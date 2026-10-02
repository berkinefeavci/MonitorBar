import Foundation

struct BrightnessSchedule {
    var nightStart: Int
    var nightEnd: Int

    func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let now = hour * 60 + minute
        if nightStart == nightEnd { return false }
        if nightStart < nightEnd { return now >= nightStart && now < nightEnd }
        return now >= nightStart || now < nightEnd
    }
}
