import CoreData

// MARK: - Core Data model configuration
extension DoseLog {
    // Remove the duplicate fetchRequest method - Xcode generates this automatically
    
    // Add any custom computed properties or methods here
    var formattedDateTime: String {
        guard let dateTime = dateTime else { return "Not scheduled" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: dateTime)
    }
}

// Note: Medication extensions are defined in MedicationExtensions.swift
// to avoid duplicate declarations
