import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample medications for preview
        let sampleMedications = [
            ("Aspirin", 7, 2, "After Food", 14),
            ("Vitamin D", 30, 1, "Before Food", 30),
            ("Antibiotics", 5, 3, "With Food", 15)
        ]
        
        for (name, days, timesPerDay, foodTiming, stock) in sampleMedications {
            let medication = Medication(context: viewContext)
            medication.name = name
            medication.days = Int16(days)
            medication.timesPerDay = Int16(timesPerDay)
            medication.foodTiming = foodTiming
            medication.stock = Int16(stock)
            medication.taken = false
            
            // Generate sample times
            var sampleTimes: [Date] = []
            let calendar = Calendar.current
            let baseDate = Date()
            
            for i in 0..<timesPerDay {
                let hour = 8 + (i * (12 / max(timesPerDay - 1, 1)))
                if let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate) {
                    sampleTimes.append(time)
                }
            }
            
            medication.time = sampleTimes.first ?? Date()
            medication.times = sampleTimes
            
            // Create dose logs for preview
            let startOfToday = calendar.startOfDay(for: Date())
            
            for dayOffset in 0..<min(3, Int(days)) { // Only create 3 days worth for preview
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
                
                for time in sampleTimes {
                    let components = calendar.dateComponents([.hour, .minute], from: time)
                    
                    if let scheduledDate = calendar.date(
                        bySettingHour: components.hour ?? 0,
                        minute: components.minute ?? 0,
                        second: 0,
                        of: dayDate
                    ) {
                        let dose = DoseLog(context: viewContext)
                        dose.dateTime = scheduledDate
                        dose.isTaken = dayOffset == 0 && scheduledDate < Date() && medication.name == "Aspirin"
                        dose.medication = medication
                    }
                }
            }
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "pill_reminder")

        // Configure the container before loading
        configureContainer(inMemory: inMemory)
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // Log the error but don't crash in production
                print("Core Data error: \(error), \(error.userInfo)")
                
                #if DEBUG
                // Only fatal error in debug mode
                if error.code == 134060 && error.domain == NSCocoaErrorDomain {
                    // This is the CloudKit transformer error - provide helpful message
                    fatalError("CloudKit integration error: Ensure value transformers are registered in AppDelegate/App init. Error: \(error)")
                } else {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
                #else
                // In production, try to recover
                print("Attempting to recover from Core Data error...")
                #endif
            } else {
                // Successfully loaded
                print("Core Data store loaded successfully: \(storeDescription.url?.absoluteString ?? "in-memory")")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Configure merge policy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up observers for iCloud sync
        setupCloudKitObservers()
    }
    
    private func configureContainer(inMemory: Bool) {
        guard let storeDescription = container.persistentStoreDescriptions.first else { return }
        
        if inMemory {
            storeDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Only enable CloudKit if properly configured
            #if !DEBUG
            // Enable CloudKit for production builds only
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            #endif
        }
        
        // Enable automatic migration
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        
        // Set timeout for SQLite
        storeDescription.setOption(30 as NSNumber, forKey: NSPersistentStoreTimeoutOption)
        
        // Set file protection
        storeDescription.setOption(FileProtectionType.complete as NSString, forKey: NSPersistentStoreFileProtectionKey)
    }
    
    private func setupCloudKitObservers() {
        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }
    
    @objc private func handleRemoteChange(_ notification: Notification) {
        // Process remote changes
        container.viewContext.perform {
            // Merge changes
            self.container.viewContext.refreshAllObjects()
            
            // Post notification for UI updates
            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
        }
    }
}

// MARK: - Core Data Helpers
extension PersistenceController {
    
    /// Performs a save operation with proper error handling
    func save(completion: ((Error?) -> Void)? = nil) {
        let context = container.viewContext
        
        guard context.hasChanges else {
            completion?(nil)
            return
        }
        
        context.perform {
            do {
                try context.save()
                completion?(nil)
            } catch {
                // Log the error
                let nsError = error as NSError
                print("Core Data Save Error: \(nsError), \(nsError.userInfo)")
                
                // Rollback changes
                context.rollback()
                
                completion?(error)
            }
        }
    }
    
    /// Resets all data (useful for debugging)
    func resetAllData(completion: @escaping (Error?) -> Void) {
        let coordinator = container.persistentStoreCoordinator
        
        container.viewContext.perform {
            let entities = self.container.managedObjectModel.entities
            
            for entity in entities {
                guard let entityName = entity.name else { continue }
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs
                
                do {
                    let result = try coordinator.execute(deleteRequest, with: self.container.viewContext) as? NSBatchDeleteResult
                    
                    if let objectIDArray = result?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: objectIDArray]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                    }
                } catch {
                    print("Failed to delete \(entityName): \(error)")
                    completion(error)
                    return
                }
            }
            
            completion(nil)
        }
    }
    
    /// Performs cleanup of old dose logs
    func cleanupOldDoseLogs(olderThan days: Int = 30) {
        let context = container.viewContext
        let calendar = Calendar.current
        
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }
        
        context.perform {
            let fetchRequest: NSFetchRequest<DoseLog> = DoseLog.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "dateTime < %@", cutoffDate as NSDate)
            
            do {
                let oldLogs = try context.fetch(fetchRequest)
                
                for log in oldLogs {
                    context.delete(log)
                }
                
                if context.hasChanges {
                    try context.save()
                    print("Cleaned up \(oldLogs.count) old dose logs")
                }
            } catch {
                print("Failed to cleanup old dose logs: \(error)")
            }
        }
    }
    
    /// Export data for backup
    func exportData() -> Data? {
        let context = container.viewContext
        var exportData: Data?
        
        context.performAndWait {
            do {
                let medications = try context.fetch(Medication.fetchRequest())
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                
                let medicationData = medications.map { medication in
                    return [
                        "name": medication.name ?? "",
                        "days": medication.days,
                        "stock": medication.stock,
                        "foodTiming": medication.foodTiming ?? "",
                        "timesPerDay": medication.timesPerDay,
                        "isCritical": medication.isCritical
                    ] as [String : Any]
                }
                
                exportData = try JSONSerialization.data(withJSONObject: medicationData, options: .prettyPrinted)
            } catch {
                print("Failed to export data: \(error)")
            }
        }
        
        return exportData
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let dataStoreError = Notification.Name("dataStoreError")
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}
