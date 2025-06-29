//
//  PersistentAlertHandler.swift
//  pill_reminder
//
//  Created by Akash Lakshmipathy on 29/06/25.
//

import Foundation
import CoreData
import UserNotifications
import UIKit

// MARK: - Persistent Alert Handler
class PersistentAlertHandler {
    static let shared = PersistentAlertHandler()
    
    private var checkTimers: [String: Timer] = [:]
    private let queue = DispatchQueue(label: "com.pillreminder.persistentalerts", attributes: .concurrent)
    
    private init() {
        // Listen for app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Start Monitoring Critical Dose
    func startMonitoring(
        dose: DoseLog,
        medication: Medication,
        context: NSManagedObjectContext
    ) {
        guard medication.isCritical,
              let doseTime = dose.dateTime,
              let medicationId = medication.objectID.uriRepresentation().absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            return
        }
        
        let doseIdentifier = "\(medicationId)_\(doseTime.timeIntervalSince1970)"
        
        queue.async(flags: .barrier) { [weak self] in
            // Cancel any existing timer
            self?.checkTimers[doseIdentifier]?.invalidate()
            
            // Schedule initial check after 30 minutes
            DispatchQueue.main.async {
                let timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
                    self?.checkDoseStatus(
                        doseIdentifier: doseIdentifier,
                        dose: dose,
                        medication: medication,
                        context: context
                    )
                }
                
                self?.queue.async(flags: .barrier) {
                    self?.checkTimers[doseIdentifier] = timer
                }
                
                // Auto-stop after 8 hours
                DispatchQueue.main.asyncAfter(deadline: .now() + 28800) {
                    self?.stopMonitoring(doseIdentifier: doseIdentifier)
                }
            }
        }
    }
    
    // MARK: - Stop Monitoring
    func stopMonitoring(doseIdentifier: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.checkTimers[doseIdentifier]?.invalidate()
            self?.checkTimers.removeValue(forKey: doseIdentifier)
        }
    }
    
    func stopMonitoringMedication(_ medicationId: String) {
        queue.async(flags: .barrier) { [weak self] in
            let keysToRemove = self?.checkTimers.keys.filter { $0.hasPrefix(medicationId) } ?? []
            for key in keysToRemove {
                self?.checkTimers[key]?.invalidate()
                self?.checkTimers.removeValue(forKey: key)
            }
        }
    }
    
    func stopAllMonitoring() {
        queue.async(flags: .barrier) { [weak self] in
            self?.checkTimers.values.forEach { $0.invalidate() }
            self?.checkTimers.removeAll()
        }
    }
    
    // MARK: - Check Dose Status
    private func checkDoseStatus(
        doseIdentifier: String,
        dose: DoseLog,
        medication: Medication,
        context: NSManagedObjectContext
    ) {
        context.perform { [weak self] in
            // Refresh the dose object
            context.refresh(dose, mergeChanges: true)
            
            // Check if dose was taken
            if dose.isTaken {
                // Stop monitoring this dose
                self?.stopMonitoring(doseIdentifier: doseIdentifier)
                
                // Cancel any pending follow-up notifications
                if let medicationId = medication.objectID.uriRepresentation().absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                    NotificationManager.shared.cancelFollowUpsForDose(doseIdentifier)
                }
                return
            }
            
            // Check if dose is still within the eligible window
            guard let doseTime = dose.dateTime else { return }
            let timeSinceScheduled = Date().timeIntervalSince(doseTime)
            
            if timeSinceScheduled > 7200 { // More than 2 hours past
                // Dose missed - stop monitoring but log it
                self?.stopMonitoring(doseIdentifier: doseIdentifier)
                self?.logMissedCriticalDose(medication: medication, doseTime: doseTime)
                return
            }
            
            // Still within window - check how many reminders have been sent
            self?.checkAndSendAdditionalReminder(
                medication: medication,
                doseTime: doseTime,
                timeSinceScheduled: timeSinceScheduled
            )
        }
    }
    
    // MARK: - Send Additional Reminders
    private func checkAndSendAdditionalReminder(
        medication: Medication,
        doseTime: Date,
        timeSinceScheduled: TimeInterval
    ) {
        guard let medicationName = medication.name,
              let foodTiming = medication.foodTiming else { return }
        
        // Determine follow-up level based on time elapsed
        let followUpLevel: Int
        if timeSinceScheduled < 1800 { // Less than 30 min
            return // Too early for follow-up
        } else if timeSinceScheduled < 3600 { // 30-60 min
            followUpLevel = 1
        } else if timeSinceScheduled < 5400 { // 60-90 min
            followUpLevel = 2
        } else { // 90+ min
            followUpLevel = 3
        }
        
        // Check if we've already sent this level of follow-up
        let medicationId = medication.objectID.uriRepresentation().absoluteString
        let followUpId = "\(medicationId)_persistent_\(followUpLevel)"
        
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let alreadySent = requests.contains { $0.identifier == followUpId }
            
            if !alreadySent {
                // Send the persistent reminder
                self.sendPersistentReminder(
                    medicationId: medicationId,
                    medicationName: medicationName,
                    foodTiming: foodTiming,
                    doseTime: doseTime,
                    followUpLevel: followUpLevel
                )
            }
        }
    }
    
    private func sendPersistentReminder(
        medicationId: String,
        medicationName: String,
        foodTiming: String,
        doseTime: Date,
        followUpLevel: Int
    ) {
        let content = UNMutableNotificationContent()
        
        switch followUpLevel {
        case 1:
            content.title = "⚠️ Reminder: \(medicationName)"
            content.body = "Your critical medication is overdue. \(foodTiming)"
        case 2:
            content.title = "🚨 Urgent: \(medicationName)"
            content.body = "Please take your critical medication immediately! \(foodTiming)"
        default:
            content.title = "⛔️ CRITICAL: \(medicationName)"
            content.body = "Your critical medication is severely overdue! Take it now or contact your doctor."
        }
        
        content.sound = .defaultCritical
        content.categoryIdentifier = NotificationCategory.criticalAlert
        content.threadIdentifier = "critical_\(medicationId)"
        content.badge = NSNumber(value: followUpLevel + 1)
        
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        
        content.userInfo = [
            "medicationId": medicationId,
            "medicationName": medicationName,
            "doseTime": doseTime.timeIntervalSince1970,
            "isCritical": true,
            "isPersistent": true,
            "followUpLevel": followUpLevel
        ]
        
        let request = UNNotificationRequest(
            identifier: "\(medicationId)_persistent_\(followUpLevel)",
            content: content,
            trigger: nil // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending persistent reminder: \(error)")
            } else {
                print("Sent persistent reminder level \(followUpLevel) for \(medicationName)")
            }
        }
    }
    
    // MARK: - Logging
    private func logMissedCriticalDose(medication: Medication, doseTime: Date) {
        // Log missed critical doses for analytics or doctor reports
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        print("⚠️ Critical dose missed: \(medication.name ?? "Unknown") at \(formatter.string(from: doseTime))")
        
        // In a real app, you might want to:
        // 1. Save this to a separate Core Data entity for tracking
        // 2. Send analytics
        // 3. Show in a "missed doses" report
        // 4. Potentially notify a caregiver if configured
    }
    
    // MARK: - App Lifecycle
    @objc private func appDidBecomeActive() {
        // When app becomes active, check all monitored doses
        queue.sync {
            print("App became active, \(checkTimers.count) doses being monitored")
        }
    }
    
    @objc private func appWillResignActive() {
        // App going to background - timers will continue
        queue.sync {
            print("App resigning active, \(checkTimers.count) doses will continue monitoring")
        }
    }
    
    // MARK: - Critical Dose Check on App Launch
    func checkAllCriticalDosesOnLaunch(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Medication> = Medication.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isCritical == true")
        
        do {
            let criticalMedications = try context.fetch(fetchRequest)
            
            for medication in criticalMedications {
                // Check today's doses
                let todayDoses = medication.todayDoses
                
                for dose in todayDoses {
                    if !dose.isTaken && dose.isEligibleForActions {
                        // Start monitoring this dose
                        startMonitoring(dose: dose, medication: medication, context: context)
                    }
                }
            }
        } catch {
            print("Error checking critical doses: \(error)")
        }
    }
}

// MARK: - Core Data Integration
extension Medication {
    func startPersistentMonitoring(context: NSManagedObjectContext) {
        guard isCritical else { return }
        
        // Monitor all eligible doses
        let eligibleDoses = todayDoses.filter { !$0.isTaken && $0.isEligibleForActions }
        
        for dose in eligibleDoses {
            PersistentAlertHandler.shared.startMonitoring(
                dose: dose,
                medication: self,
                context: context
            )
        }
    }
    
    func stopPersistentMonitoring() {
        guard let medicationId = objectID.uriRepresentation().absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
        
        PersistentAlertHandler.shared.stopMonitoringMedication(medicationId)
    }
}
