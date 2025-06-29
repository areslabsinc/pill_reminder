import UserNotifications
import UIKit

// MARK: - Notification Categories
struct NotificationCategory {
    static let medicationReminder = "MEDICATION_REMINDER"
    static let followUpReminder = "FOLLOWUP_REMINDER"
    static let criticalAlert = "CRITICAL_ALERT"
}

// MARK: - Notification Actions
struct NotificationAction {
    static let take = "TAKE_ACTION"
    static let snooze = "SNOOZE_ACTION"
    static let skip = "SKIP_ACTION"
}

// MARK: - Rich Notification Content
class RichNotificationContent {
    static func createMedicationNotification(
        medication: MedicationNotificationData,
        isCritical: Bool = false,
        isFollowUp: Bool = false
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        
        // Title and body
        if isFollowUp {
            content.title = "Follow-up: \(medication.name)"
            content.body = "You haven't taken your medication yet. \(medication.foodTiming)"
        } else {
            content.title = "Time for \(medication.name)"
            content.body = medication.foodTiming
        }
        
        // Subtitle with additional info
        if medication.stock < 5 && medication.stock > 0 {
            content.subtitle = "Only \(medication.stock) pills remaining"
        } else if medication.stock == 0 {
            content.subtitle = "Out of stock - please refill"
        }
        
        // Category for actions
        content.categoryIdentifier = isCritical ? NotificationCategory.criticalAlert :
                                    (isFollowUp ? NotificationCategory.followUpReminder :
                                     NotificationCategory.medicationReminder)
        
        // Sound configuration
        if isCritical {
            // Use system critical sound for important medications
            content.sound = .defaultCritical
            
            // Add additional prominence through other means
            content.threadIdentifier = "critical_\(medication.id)"
            content.targetContentIdentifier = "critical_\(medication.id)"
            
            // Add an alert subtitle to indicate importance
            if content.subtitle.isEmpty {
                content.subtitle = "Critical medication reminder"
            }
        } else if isFollowUp {
            // Use a slightly more prominent sound for follow-ups
            content.sound = .default
        } else {
            // Regular notification sound
            content.sound = .default
        }
        
        // User info for handling actions
        content.userInfo = [
            "medicationId": medication.id,
            "medicationName": medication.name,
            "doseTime": medication.doseTime.timeIntervalSince1970,
            "stock": medication.stock,
            "isCritical": isCritical,
            "isFollowUp": isFollowUp
        ]
        
        // Thread identifier for grouping
        content.threadIdentifier = medication.id
        
        // Badge
        content.badge = NSNumber(value: 1)
        
        // Interruption level
        if #available(iOS 15.0, *) {
            if isCritical {
                content.interruptionLevel = .timeSensitive
                content.relevanceScore = 1.0 // Highest relevance for critical meds
            } else if isFollowUp {
                content.interruptionLevel = .timeSensitive
                content.relevanceScore = 0.8
            } else {
                content.interruptionLevel = .active
                content.relevanceScore = 0.5
            }
        }
        
        return content
    }
}

// MARK: - Medication Notification Data
struct MedicationNotificationData {
    let id: String
    let name: String
    let foodTiming: String
    let doseTime: Date
    let stock: Int
}

// MARK: - Notification Actions Setup
extension NotificationManager {
    func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()
        
        // Take action
        let takeAction = UNNotificationAction(
            identifier: NotificationAction.take,
            title: "Take",
            options: [.authenticationRequired, .foreground]
        )
        
        // Snooze action
        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze,
            title: "Snooze 15min",
            options: []
        )
        
        // Skip action
        let skipAction = UNNotificationAction(
            identifier: NotificationAction.skip,
            title: "Skip Dose",
            options: [.destructive]
        )
        
        // Standard medication reminder category
        let medicationCategory = UNNotificationCategory(
            identifier: NotificationCategory.medicationReminder,
            actions: [takeAction, snoozeAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Follow-up reminder category (no skip option)
        let followUpCategory = UNNotificationCategory(
            identifier: NotificationCategory.followUpReminder,
            actions: [takeAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Critical medication category
        let criticalCategory = UNNotificationCategory(
            identifier: NotificationCategory.criticalAlert,
            actions: [takeAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        center.setNotificationCategories([
            medicationCategory,
            followUpCategory,
            criticalCategory
        ])
    }
    
    // Schedule smart follow-up reminder
    func scheduleFollowUpReminder(
        for medicationId: String,
        medicationName: String,
        foodTiming: String,
        originalDoseTime: Date,
        delay: TimeInterval = 1800, // 30 minutes default
        followUpLevel: Int = 1
    ) {
        let content = UNMutableNotificationContent()
        
        // Escalating urgency based on follow-up level
        switch followUpLevel {
        case 1:
            content.title = "Reminder: \(medicationName)"
            content.body = "You haven't taken your medication yet. \(foodTiming)"
            content.sound = .default
        case 2:
            content.title = "Important: \(medicationName)"
            content.body = "Please take your medication now. \(foodTiming)"
            content.sound = .defaultCritical
        case 3:
            content.title = "Urgent: \(medicationName)"
            content.body = "Critical medication overdue! \(foodTiming)"
            content.sound = .defaultCritical
        default:
            content.title = "Critical Alert: \(medicationName)"
            content.body = "You must take your medication immediately! \(foodTiming)"
            content.sound = .defaultCritical
        }
        
        content.categoryIdentifier = NotificationCategory.followUpReminder
        content.threadIdentifier = medicationId
        
        content.userInfo = [
            "medicationId": medicationId,
            "medicationName": medicationName,
            "isFollowUp": true,
            "followUpLevel": followUpLevel,
            "originalDoseTime": originalDoseTime.timeIntervalSince1970
        ]
        
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = min(1.0, 0.5 + (Double(followUpLevel) * 0.15))
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: delay,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "\(medicationId)_followup_\(followUpLevel)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling follow-up reminder: \(error)")
            }
        }
    }
    
    // Cancel follow-up reminder
    func cancelFollowUpReminder(for medicationId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(medicationId)_followup"]
        )
    }
}
