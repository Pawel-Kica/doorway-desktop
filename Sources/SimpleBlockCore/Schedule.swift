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
}
