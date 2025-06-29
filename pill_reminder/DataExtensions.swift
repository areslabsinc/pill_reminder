import Foundation

extension Date {
    var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    func isSameDay(as date: Date) -> Bool {
        return Calendar.current.isDate(self, inSameDayAs: date)
    }
    
    func addingDays(_ days: Int) -> Date? {
        return Calendar.current.date(byAdding: .day, value: days, to: self)
    }
    
    var isInPast: Bool {
        return self < Date()
    }
    
    var isInFuture: Bool {
        return self > Date()
    }
    
    func timeIntervalUntilNow() -> TimeInterval {
        return Date().timeIntervalSince(self)
    }
}
