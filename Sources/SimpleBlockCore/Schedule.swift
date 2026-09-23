import Foundation

/// A scheduled session's days plus a From/To time of day.
/// From > To wraps past midnight, and the part after midnight belongs to the day it started on.
/// From == To covers the whole day.
public struct Schedule: Codable, Equatable {
    /// Calendar weekdays, 1 = Sunday ... 7 = Saturday.
    public var days: Set<Int>
    /// Minutes since midnight.
    public var from: Int
    public var to: Int

    public init(days: Set<Int> = Set(1...7), from: Int = 0, to: Int = 0) {
        self.days = days
        self.from = from
        self.to = to
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = parts.weekday!
        let minute = parts.hour! * 60 + parts.minute!
        let yesterday = weekday == 1 ? 7 : weekday - 1

        if from == to { return days.contains(weekday) }
        if from < to { return days.contains(weekday) && minute >= from && minute < to }
        return (days.contains(weekday) && minute >= from) || (days.contains(yesterday) && minute < to)
    }

    /// When the window active at `date` ends. Nil when not active, or when it never ends (every day, all day).
    /// All-day windows on consecutive days merge into one.
    public func end(of date: Date, calendar: Calendar = .current) -> Date? {
        guard isActive(at: date, calendar: calendar) else { return nil }
        if from == to {
            var midnight = calendar.startOfDay(for: date)
            for _ in 0..<7 {
                midnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
                if !isActive(at: midnight, calendar: calendar) { return midnight }
            }
            return nil
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.hour! * 60 + parts.minute!
        // Overnight and still before midnight: the window ends tomorrow.
        let day = from > to && minute >= from ? calendar.date(byAdding: .day, value: 1, to: date)! : date
        return calendar.date(bySettingHour: to / 60, minute: to % 60, second: 0, of: day)
    }

    /// When the next window starts after `date`, all-day ones at midnight. Nil when no day is picked.
    /// Meant for a schedule that's off at `date`.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let start = from == to ? 0 : from
        let today = calendar.startOfDay(for: date)
        // Eight days, so a single day that already started today comes round again next week.
        for offset in 0...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            guard days.contains(calendar.component(.weekday, from: day)),
                  let next = calendar.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: day),
                  next > date else { continue }
            return next
        }
        return nil
    }

    /// Weekdays in the order Settings shows them.
    public static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    /// "Every day", "Weekdays", "Weekends", "No days", else short names Monday first: "Mon, Wed, Fri".
    public func daysSummary(calendar: Calendar = .current) -> String {
        switch days {
        case Set(1...7): "Every day"
        case Set(2...6): "Weekdays"
        case [1, 7]: "Weekends"
        case []: "No days"
        default: Self.mondayFirst.filter(days.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
    }
}

/// Time left, rounded up to the minute: "45 min", "13 h 35 min", "2 d 3 h" from a day up.
public func timeLeft(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded(.up)))
    if minutes < 60 { return "\(minutes) min" }
    if minutes < 24 * 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
    let hours = minutes % (24 * 60) / 60
    return hours == 0 ? "\(minutes / (24 * 60)) d" : "\(minutes / (24 * 60)) d \(hours) h"
}
