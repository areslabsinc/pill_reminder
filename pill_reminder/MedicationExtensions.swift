import Foundation
import CoreData
import CloudKit

// MARK: - Medication Extensions
extension Medication {
    // Clean up when medication is deleted
    func cleanupUserDefaults() {
        // Remove from old UserDefaults storage if it exists (for backwards compatibility)
        let key = "isCritical_\(self.objectID.uriRepresentation().absoluteString)"
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // Add cleanup method for when medication is deleted
    func cleanupPendingFollowUps() {
        NotificationManager.shared.cancelPendingFollowUpCheck(for: self.objectID)
    }
    
    // Computed properties for better performance
    var displayName: String {
        return name ?? "Unnamed Medication"
    }
    
    var remainingDoses: Int {
        return Int(max(0, stock))
    }
    
    var todayDoses: [DoseLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let doseLogs = (doseLog as? Set<DoseLog>) ?? []
        
        return doseLogs
            .filter {
                guard let date = $0.dateTime else { return false }
                return date >= startOfDay && date < endOfDay
            }
            .sorted {
                guard let date1 = $0.dateTime, let date2 = $1.dateTime else { return false }
                return date1 < date2
            }
    }
    
    var nextDose: DoseLog? {
        let now = Date()
        return todayDoses.first { dose in
            guard let doseTime = dose.dateTime, !dose.isTaken else { return false }
            return doseTime > now
        }
    }
    
    var missedDoses: [DoseLog] {
        let now = Date()
        return todayDoses.filter { dose in
            guard let doseTime = dose.dateTime else { return false }
            return !dose.isTaken && doseTime < now && now.timeIntervalSince(doseTime) > 7200
        }
    }
    
    func hasEligibleDoseToTake() -> Bool {
        let now = Date()
        for dose in todayDoses {
            if !dose.isTaken, let scheduled = dose.dateTime {
                let timeInterval = scheduled.timeIntervalSince(now)
                                
                // Eligible only within the 2-hour window
                if timeInterval > -7200 && timeInterval < 7200 {
                    return true
                }
            }
        }
        return false
    }
    
    // Get doses within time window
    func getDosesInWindow(from startTime: Date, to endTime: Date) -> [DoseLog] {
        let doseLogs = (doseLog as? Set<DoseLog>) ?? []
        
        return doseLogs
            .filter {
                guard let date = $0.dateTime else { return false }
                return date >= startTime && date <= endTime
            }
            .sorted {
                guard let date1 = $0.dateTime, let date2 = $1.dateTime else { return false }
                return date1 < date2
            }
    }
}

// MARK: - DoseLog Extensions
extension DoseLog {
    // Add a computed property to check if this dose needs a follow-up
    var needsFollowUp: Bool {
        guard let scheduledTime = dateTime, !isTaken else { return false }
        let timeSinceScheduled = Date().timeIntervalSince(scheduledTime)
        return timeSinceScheduled > 1800 && timeSinceScheduled < 7200 // Between 30 min and 2 hours
    }
    
    // Check if dose is eligible for notification actions
    var isEligibleForActions: Bool {
        guard let scheduledTime = dateTime else { return false }
        let now = Date()
        let timeInterval = scheduledTime.timeIntervalSince(now)
                
        // Eligible only if:
        // - Not taken
        // - Within 2 hours before or after scheduled time
        return !isTaken && timeInterval > -7200 && timeInterval < 7200
    }
    
    // Check if dose is missed
    var isMissed: Bool {
        guard let scheduledTime = dateTime, !isTaken else { return false }
        let now = Date()
        return now.timeIntervalSince(scheduledTime) > 7200 // More than 2 hours past
    }
    
    private static let doseCache = NSCache<NSString, NSArray>()
    
    // Get time status
    var timeStatus: DoseTimeStatus {
        guard let scheduledTime = dateTime else { return .unknown }
        
        let now = Date()
        let timeDifference = scheduledTime.timeIntervalSince(now)
        
        if isTaken {
            return .taken
        } else if timeDifference > 7200 {
            return .upcoming
        } else if timeDifference > -7200 {
            return .current
        } else {
            return .missed
        }
    }
    
    enum DoseTimeStatus {
        case taken
        case upcoming
        case current
        case missed
        case unknown
    }
}

// MARK: - Notification Helper Extensions
extension Medication {
    // Create notification data for this medication
    func createNotificationData(for doseTime: Date) -> MedicationNotificationData {
        return MedicationNotificationData(
            id: self.objectID.uriRepresentation().absoluteString,
            name: self.name ?? "Medication",
            foodTiming: self.foodTiming ?? "No specific timing",
            doseTime: doseTime,
            stock: Int(self.stock)
        )
    }
    
    // Check if any doses need follow-up reminders
    func checkForFollowUpReminders() {
        let doseLogs = (self.doseLog as? Set<DoseLog>) ?? []
        let now = Date()
        
        for dose in doseLogs {
            if dose.needsFollowUp {
                // Schedule a follow-up reminder
                if let doseTime = dose.dateTime {
                    NotificationManager.shared.scheduleFollowUpReminder(
                        for: self.objectID.uriRepresentation().absoluteString,
                        medicationName: self.name ?? "Medication",
                        foodTiming: self.foodTiming ?? "",
                        originalDoseTime: doseTime,
                        delay: 300 // 5 minutes for immediate follow-up
                    )
                }
            }
        }
    }
    
    // Get adherence rate
    func getAdherenceRate(days: Int = 7) -> Double {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else { return 0 }
        
        let dosesInPeriod = getDosesInWindow(from: startDate, to: endDate)
        let pastDoses = dosesInPeriod.filter { dose in
            guard let doseTime = dose.dateTime else { return false }
            return doseTime < Date()
        }
        
        guard !pastDoses.isEmpty else { return 1.0 }
        
        let takenDoses = pastDoses.filter { $0.isTaken }
        return Double(takenDoses.count) / Double(pastDoses.count)
    }
    
    // Validate stock levels
    func validateStock() {
        if stock < 0 {
            stock = 0
        }
        
        // Check if stock needs refill
        let daysOfStockRemaining = Int(stock) / Int(max(1, timesPerDay))
        if daysOfStockRemaining <= 3 && stock > 0 {
            // Could trigger a low stock notification here
            print("Low stock warning for \(name ?? "medication"): \(daysOfStockRemaining) days remaining")
        }
    }
}

extension Notification.Name {
    static let medicationCriticalStatusChanged = Notification.Name("medicationCriticalStatusChanged")
}

// MARK: - Core Data Helpers
extension Medication {
    // Safe save with error handling
    func save(in context: NSManagedObjectContext) throws {
        validateStock()
        
        if context.hasChanges {
            try context.save()
        }
    }
    
    // Create a duplicate medication (useful for templates)
    func duplicate(in context: NSManagedObjectContext) -> Medication {
        let newMedication = Medication(context: context)
        newMedication.name = self.name
        newMedication.days = self.days
        newMedication.timesPerDay = self.timesPerDay
        newMedication.foodTiming = self.foodTiming
        newMedication.stock = self.stock
        newMedication.times = self.times
        newMedication.time = self.time
        newMedication.taken = false
        newMedication.isCritical = self.isCritical
        
        return newMedication
    }
}
