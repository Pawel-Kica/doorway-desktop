import Foundation

/// The one global schedule: enabled weekdays plus a From/To time of day.
/// From > To wraps past midnight, and the part after midnight belongs to the day it started on.
/// From == To covers the whole day.
public struct Schedule: Equatable {
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
}
