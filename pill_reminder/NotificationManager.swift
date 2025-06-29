import UserNotifications
import Foundation
import CoreData

class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    // Thread-safe serial queue for all notification operations
    private let notificationQueue = DispatchQueue(label: "com.pillreminder.notifications", qos: .userInitiated)
    
    // Track active scheduling operations to prevent overlaps
    private var activeSchedulingOperations = Set<String>()
    private let schedulingLock = NSLock()
    
    // Persistent alert tracking
    private var persistentAlertTimers: [String: Timer] = [:]
    private let persistentAlertQueue = DispatchQueue(label: "com.pillreminder.persistentalerts")

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests permission to send notifications.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            } else {
                print("Permission granted: \(granted)")
                if granted {
                    DispatchQueue.main.async {
                        self.setupNotificationCategories()
                    }
                }
            }
        }
    }

    func scheduleNotifications(
        id: String,
        title: String,
        body: String,
        timesPerDay: [Date],
        numberOfDays: Int,
        stock: Int = 0,
        isCritical: Bool = false
    ) {
        notificationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if already scheduling
            self.schedulingLock.lock()
            if self.activeSchedulingOperations.contains(id) {
                self.schedulingLock.unlock()
                print("Already scheduling notifications for \(id), skipping")
                return
            }
            self.activeSchedulingOperations.insert(id)
            self.schedulingLock.unlock()
            
            // Cancel existing notifications synchronously
            let semaphore = DispatchSemaphore(value: 0)
            self.cancelNotifications(for: id) {
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5.0)
            
            // Schedule new notifications
            if isCritical {
                self.scheduleCriticalMedicationNotifications(
                    id: id,
                    title: title,
                    body: body,
                    timesPerDay: timesPerDay,
                    numberOfDays: numberOfDays,
                    stock: stock
                )
            } else {
                self.scheduleRegularNotifications(
                    id: id,
                    title: title,
                    body: body,
                    timesPerDay: timesPerDay,
                    numberOfDays: numberOfDays,
                    stock: stock
                )
            }
            
            // Remove from active operations
            self.schedulingLock.lock()
            self.activeSchedulingOperations.remove(id)
            self.schedulingLock.unlock()
        }
    }
    
    private func scheduleRegularNotifications(
        id: String,
        title: String,
        body: String,
        timesPerDay: [Date],
        numberOfDays: Int,
        stock: Int
    ) {
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        let timeZone = TimeZone.current
        
        var notificationRequests: [UNNotificationRequest] = []
        
        // Limit to prevent system overload
        let maxDays = min(numberOfDays, 30)
        let maxNotifications = 64
        var notificationCount = 0

        for dayOffset in 0..<maxDays {
            guard let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }

            for (index, time) in timesPerDay.enumerated() {
                if notificationCount >= maxNotifications {
                    print("Reached notification limit for \(id)")
                    break
                }
                
                var triggerDateComponents = calendar.dateComponents([.hour, .minute], from: time)
                let baseDateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                
                triggerDateComponents.year = baseDateComponents.year
                triggerDateComponents.month = baseDateComponents.month
                triggerDateComponents.day = baseDateComponents.day
                triggerDateComponents.timeZone = timeZone
                
                guard let triggerDate = calendar.date(from: triggerDateComponents) else { continue }

                // Skip dates in the past
                if triggerDate <= Date() {
                    continue
                }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.categoryIdentifier = NotificationCategory.medicationReminder
                content.threadIdentifier = id
                content.badge = NSNumber(value: 1)
                
                // Add subtitle for low stock
                if stock > 0 && stock < 5 {
                    content.subtitle = "Only \(stock) pills remaining"
                } else if stock == 0 {
                    content.subtitle = "Out of stock - please refill"
                }
                
                content.userInfo = [
                    "medicationId": id,
                    "medicationName": title.replacingOccurrences(of: "Take ", with: ""),
                    "doseTime": triggerDate.timeIntervalSince1970,
                    "stock": stock,
                    "isCritical": false
                ]

                let requestID = "\(id)_day\(dayOffset)_time\(index)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
                
                notificationRequests.append(request)
                notificationCount += 1
            }
            
            if notificationCount >= maxNotifications {
                break
            }
        }
        
        // Batch add notifications
        for request in notificationRequests {
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification \(request.identifier): \(error.localizedDescription)")
                }
            }
        }
        
        print("Scheduled \(notificationRequests.count) notifications for \(id)")
    }

    private func scheduleCriticalMedicationNotifications(
        id: String,
        title: String,
        body: String,
        timesPerDay: [Date],
        numberOfDays: Int,
        stock: Int
    ) {
        let calendar = Calendar.current
        let center = UNUserNotificationCenter.current()
        let timeZone = TimeZone.current
        
        var notificationRequests: [UNNotificationRequest] = []
        
        let maxDays = min(numberOfDays, 30)
        let maxNotifications = 64
        var notificationCount = 0

        for dayOffset in 0..<maxDays {
            guard let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }

            for (index, time) in timesPerDay.enumerated() {
                if notificationCount >= maxNotifications {
                    print("Reached notification limit for critical medication \(id)")
                    break
                }
                
                var triggerDateComponents = calendar.dateComponents([.hour, .minute], from: time)
                let baseDateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
                
                triggerDateComponents.year = baseDateComponents.year
                triggerDateComponents.month = baseDateComponents.month
                triggerDateComponents.day = baseDateComponents.day
                triggerDateComponents.timeZone = timeZone
                
                guard let triggerDate = calendar.date(from: triggerDateComponents) else { continue }

                if triggerDate <= Date() {
                    continue
                }

                // Create notification data
                let medicationData = MedicationNotificationData(
                    id: id,
                    name: title.replacingOccurrences(of: "Take ", with: ""),
                    foodTiming: body,
                    doseTime: triggerDate,
                    stock: stock
                )
                
                let content = RichNotificationContent.createMedicationNotification(
                    medication: medicationData,
                    isCritical: true,
                    isFollowUp: false
                )

                let requestID = "\(id)_day\(dayOffset)_time\(index)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
                
                notificationRequests.append(request)
                notificationCount += 1
                
                // Schedule persistent follow-ups for critical medications
                schedulePersistentFollowUps(
                    for: id,
                    medicationName: medicationData.name,
                    foodTiming: medicationData.foodTiming,
                    originalDoseTime: triggerDate,
                    doseIdentifier: requestID
                )
            }
            
            if notificationCount >= maxNotifications {
                break
            }
        }
        
        // Batch add notifications
        for request in notificationRequests {
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling critical notification \(request.identifier): \(error.localizedDescription)")
                }
            }
        }
        
        print("Scheduled \(notificationRequests.count) critical notifications for \(id)")
    }
    
    // MARK: - Enhanced Persistent Follow-up System
    
    private func schedulePersistentFollowUps(
        for medicationId: String,
        medicationName: String,
        foodTiming: String,
        originalDoseTime: Date,
        doseIdentifier: String
    ) {
        // Schedule escalating reminders
        let followUpSchedule = [
            (delay: 1800, urgency: "Reminder"),      // 30 minutes
            (delay: 3600, urgency: "Important"),     // 1 hour
            (delay: 7200, urgency: "Urgent"),        // 2 hours
            (delay: 14400, urgency: "Critical")      // 4 hours
        ]
        
        for (index, schedule) in followUpSchedule.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "⚠️ \(schedule.urgency): \(medicationName)"
            content.body = "You haven't taken your critical medication. \(foodTiming)"
            
            // Use escalating sounds
            switch index {
            case 0:
                content.sound = .default
            case 1:
                content.sound = .defaultCritical
            case 2, 3:
                // For maximum urgency, use defaultCritical with repeat
                content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
            default:
                content.sound = .defaultCritical
            }
            
            content.categoryIdentifier = NotificationCategory.criticalAlert
            content.threadIdentifier = medicationId
            content.badge = NSNumber(value: index + 2) // Increasing badge count
            
            // Add urgency indicator to subtitle
            content.subtitle = "⏰ \(schedule.urgency) - Please take immediately"
            
            content.userInfo = [
                "medicationId": medicationId,
                "medicationName": medicationName,
                "isFollowUp": true,
                "isCritical": true,
                "followUpLevel": index + 1,
                "originalDoseTime": originalDoseTime.timeIntervalSince1970,
                "doseIdentifier": doseIdentifier
            ]
            
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .critical
                content.relevanceScore = Double(followUpSchedule.count - index) / Double(followUpSchedule.count)
            }
            
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(schedule.delay),
                repeats: false
            )
            
            let request = UNNotificationRequest(
                identifier: "\(doseIdentifier)_followup_\(index)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling follow-up level \(index + 1): \(error)")
                }
            }
        }
        
        // Also start a persistent check timer for this dose
        startPersistentCheck(for: doseIdentifier, medicationId: medicationId, originalDoseTime: originalDoseTime)
    }
    
    // MARK: - Persistent Check System
    
    private func startPersistentCheck(for doseIdentifier: String, medicationId: String, originalDoseTime: Date) {
        persistentAlertQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any existing timer for this dose
            self.persistentAlertTimers[doseIdentifier]?.invalidate()
            
            // Create a timer that checks every 30 minutes if the dose has been taken
            let timer = Timer(timeInterval: 1800, repeats: true) { _ in
                self.checkCriticalDoseTaken(
                    doseIdentifier: doseIdentifier,
                    medicationId: medicationId,
                    originalDoseTime: originalDoseTime
                )
            }
            
            // Add to run loop
            RunLoop.current.add(timer, forMode: .common)
            self.persistentAlertTimers[doseIdentifier] = timer
            
            // Stop checking after 8 hours
            DispatchQueue.main.asyncAfter(deadline: .now() + 28800) { // 8 hours
                self.stopPersistentCheck(for: doseIdentifier)
            }
        }
    }
    
    private func stopPersistentCheck(for doseIdentifier: String) {
        persistentAlertQueue.async { [weak self] in
            self?.persistentAlertTimers[doseIdentifier]?.invalidate()
            self?.persistentAlertTimers.removeValue(forKey: doseIdentifier)
        }
    }
    
    private func checkCriticalDoseTaken(doseIdentifier: String, medicationId: String, originalDoseTime: Date) {
        // This would need to check Core Data to see if the dose was taken
        // For now, we'll just log it
        print("Checking if critical dose \(doseIdentifier) was taken...")
        
        // In a real implementation, you would:
        // 1. Query Core Data for the dose status
        // 2. If not taken and within window, send another reminder
        // 3. If taken, cancel remaining follow-ups and stop the timer
    }
    
    // MARK: - Cancel Methods
    
    /// Cancels all scheduled notifications for a given medication ID.
    func cancelNotifications(for id: String, completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let matchingIDs = requests
                .filter { $0.identifier.hasPrefix(id) }
                .map { $0.identifier }

            if !matchingIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: matchingIDs)
                print("Canceled \(matchingIDs.count) notifications for \(id)")
            }
            
            // Also stop any persistent checks
            self.persistentAlertQueue.async {
                let keysToRemove = self.persistentAlertTimers.keys.filter { $0.hasPrefix(id) }
                for key in keysToRemove {
                    self.persistentAlertTimers[key]?.invalidate()
                    self.persistentAlertTimers.removeValue(forKey: key)
                }
            }
            
            completion?()
        }
    }
    
    func cancelFollowUpsForDose(_ doseIdentifier: String) {
        // Cancel all follow-ups for a specific dose
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let followUpIDs = requests
                .filter { $0.identifier.hasPrefix("\(doseIdentifier)_followup") }
                .map { $0.identifier }
            
            if !followUpIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: followUpIDs)
                print("Canceled \(followUpIDs.count) follow-ups for dose \(doseIdentifier)")
            }
        }
        
        // Stop persistent check
        stopPersistentCheck(for: doseIdentifier)
    }
    
    func updateBadgeCount() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let medicationNotifications = requests.filter { request in
                request.content.categoryIdentifier.contains("MEDICATION")
            }
            
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().setBadgeCount(medicationNotifications.count) { error in
                    if let error = error {
                        print("Error updating badge count: \(error)")
                    }
                }
            }
        }
    }
    
    func cancelPendingFollowUpCheck(for medicationID: NSManagedObjectID) {
        let id = medicationID.uriRepresentation().absoluteString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(id)_followup"]
        )
    }
    
    func cancelAllPendingFollowUps() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let followUpIDs = requests
                .filter { $0.identifier.contains("_followup") }
                .map { $0.identifier }
            
            if !followUpIDs.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: followUpIDs)
            }
        }
        
        // Clear all persistent check timers
        persistentAlertQueue.async { [weak self] in
            self?.persistentAlertTimers.values.forEach { $0.invalidate() }
            self?.persistentAlertTimers.removeAll()
        }
    }
    
    func performMaintenance() {
        notificationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Update badge count
            self.updateBadgeCount()
            
            // Clean up old delivered notifications
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            
            // Clean up expired pending notifications
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let now = Date()
                let expiredIDs = requests.compactMap { request -> String? in
                    guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                          let nextTriggerDate = trigger.nextTriggerDate(),
                          nextTriggerDate < now else {
                        return nil
                    }
                    return request.identifier
                }
                
                if !expiredIDs.isEmpty {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: expiredIDs)
                    print("Cleaned up \(expiredIDs.count) expired notifications")
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        // Extract dose identifier if it's a follow-up
        if let doseIdentifier = userInfo["doseIdentifier"] as? String,
           userInfo["isFollowUp"] as? Bool == true {
            // Cancel remaining follow-ups for this dose when user interacts
            cancelFollowUpsForDose(doseIdentifier)
        }
        
        switch actionIdentifier {
        case NotificationAction.take:
            // Post notification for the app to handle
            NotificationCenter.default.post(
                name: .medicationTaken,
                object: nil,
                userInfo: userInfo
            )
            
        case NotificationAction.snooze:
            if let medicationId = userInfo["medicationId"] as? String,
               let medicationName = userInfo["medicationName"] as? String {
                // Snooze for 15 minutes
                let content = UNMutableNotificationContent()
                content.title = "Snooze: \(medicationName)"
                content.body = "Time to take your medication"
                content.sound = .default
                content.categoryIdentifier = NotificationCategory.medicationReminder
                content.userInfo = userInfo
                
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 900, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(medicationId)_snooze_\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: trigger
                )
                
                center.add(request) { error in
                    if let error = error {
                        print("Error scheduling snooze: \(error)")
                    }
                }
            }
            
        case NotificationAction.skip:
            // Just dismiss, no action needed
            print("User skipped dose")
            
        default:
            // User tapped on notification
            NotificationCenter.default.post(
                name: .notificationTapped,
                object: nil,
                userInfo: userInfo
            )
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let medicationTaken = Notification.Name("medicationTaken")
    static let notificationTapped = Notification.Name("notificationTapped")
}
