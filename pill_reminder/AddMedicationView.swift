import SwiftUI
import UserNotifications
import CoreData  // Add this import to fix the NSManagedObjectContext error

struct AddMedicationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme

    var medicationToEdit: Medication?

    @State private var name: String = ""
    @State private var days: Int = 1
    @State private var timesPerDay: Int = 1
    @State private var times: [Date] = []
    @State private var foodTiming = "Before Food"
    @State private var stock: Int = 1
    @State private var isStockManuallyEdited = false
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var isCritical = false

    let foodOptions = ["Before Food", "After Food", "With Food", "No Preference"]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Medication Name")
                            .font(.soothing(.caption))
                            .foregroundColor(theme.secondaryTextColor)
                        
                        TextField("Enter medication name", text: $name)
                            .font(.soothing(.body))
                            .padding(12)
                            .background(theme.secondaryBackgroundColor)
                            .cornerRadius(CornerRadius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.medium)
                                    .stroke(name.isEmpty ? theme.errorColor.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Label("Basic Information", systemImage: "info.circle.fill")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.primaryColor)
                }

                Section {
                    // Duration Stepper
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Duration", systemImage: "calendar")
                                .font(.soothing(.body))
                                .foregroundColor(theme.textColor)
                            
                            Spacer()
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    if days > 1 {
                                        days -= 1
                                        if !isStockManuallyEdited {
                                            stock = days * timesPerDay
                                        }
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(days > 1 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(days <= 1)
                                .buttonStyle(PlainButtonStyle())
                                
                                Text("\(days) \(days == 1 ? "day" : "days")")
                                    .font(.soothing(.body))
                                    .foregroundColor(theme.primaryColor)
                                    .frame(minWidth: 60)
                                    .contentTransition(.numericText())
                                
                                Button(action: {
                                    if days < 365 {
                                        days += 1
                                        if !isStockManuallyEdited {
                                            stock = days * timesPerDay
                                        }
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(days < 365 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(days >= 365)
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Times per day
                        HStack {
                            Label("Times per day", systemImage: "clock.fill")
                                .font(.soothing(.body))
                                .foregroundColor(theme.textColor)
                            
                            Spacer()
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    if timesPerDay > 1 {
                                        let newValue = timesPerDay - 1
                                        timesPerDay = newValue
                                        adjustTimesArray(to: newValue)
                                        if !isStockManuallyEdited {
                                            stock = days * newValue
                                        }
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(timesPerDay > 1 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(timesPerDay <= 1)
                                .buttonStyle(PlainButtonStyle())
                                
                                Text("\(timesPerDay)")
                                    .font(.soothing(.body))
                                    .foregroundColor(theme.primaryColor)
                                    .frame(minWidth: 30)
                                    .contentTransition(.numericText())
                                
                                Button(action: {
                                    if timesPerDay < 10 {
                                        let newValue = timesPerDay + 1
                                        timesPerDay = newValue
                                        adjustTimesArray(to: newValue)
                                        if !isStockManuallyEdited {
                                            stock = days * newValue
                                        }
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(timesPerDay < 10 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(timesPerDay >= 10)
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(theme.secondaryBackgroundColor.opacity(0.5))
                } header: {
                    Label("Schedule Settings", systemImage: "calendar.badge.clock")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.primaryColor)
                }

                Section {
                    ForEach(0..<times.count, id: \.self) { index in
                        HStack {
                            Image(systemName: "pills.circle.fill")
                                .foregroundColor(theme.primaryColor)
                                .font(.title3)
                            
                            Text("Dose \(index + 1)")
                                .font(.soothing(.body))
                                .foregroundColor(theme.textColor)
                            
                            Spacer()
                            
                            DatePicker("", selection: Binding(
                                get: { times[index] },
                                set: { times[index] = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(CompactDatePickerStyle())
                            .accentColor(theme.primaryColor)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Label("Dose Times", systemImage: "clock.arrow.circlepath")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.primaryColor)
                }

                Section {
                    // Critical Medication Toggle
                    Toggle(isOn: $isCritical) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(isCritical ? theme.errorColor : theme.secondaryTextColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Critical Medication")
                                    .font(.soothing(.body))
                                    .foregroundColor(theme.textColor)
                                Text("Enables persistent alerts")
                                    .font(.soothing(.caption))
                                    .foregroundColor(theme.secondaryTextColor)
                            }
                        }
                    }
                    .tint(theme.errorColor)
                    
                    // Stock Control
                    VStack(spacing: 12) {
                        HStack {
                            Label("Stock", systemImage: "pills.fill")
                                .font(.soothing(.body))
                                .foregroundColor(theme.textColor)
                            
                            Spacer()
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    if stock > 0 {
                                        stock -= 1
                                        isStockManuallyEdited = true
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(stock > 0 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(stock <= 0)
                                .buttonStyle(PlainButtonStyle())
                                
                                Text("\(stock) pills")
                                    .font(.soothing(.body))
                                    .foregroundColor(theme.primaryColor)
                                    .frame(minWidth: 70)
                                    .contentTransition(.numericText())
                                
                                Button(action: {
                                    if stock < 9999 {
                                        stock += 1
                                        isStockManuallyEdited = true
                                    }
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(stock < 9999 ? theme.primaryColor : theme.secondaryTextColor)
                                }
                                .disabled(stock >= 9999)
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        if !isStockManuallyEdited {
                            Text("Auto-calculated: \(days) days × \(timesPerDay) doses/day")
                                .font(.soothing(.caption))
                                .foregroundColor(theme.secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    
                    // Food Timing
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Food Timing", systemImage: "fork.knife")
                            .font(.soothing(.caption))
                            .foregroundColor(theme.secondaryTextColor)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(foodOptions, id: \.self) { option in
                                    FoodTimingChip(
                                        title: option,
                                        isSelected: foodTiming == option,
                                        action: { foodTiming = option }
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    Label("Additional Information", systemImage: "info.bubble")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.primaryColor)
                }

                Section {
                    Button(action: saveMedication) {
                        HStack {
                            Spacer()
                            Image(systemName: medicationToEdit == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                                .font(.title3)
                            Text(medicationToEdit == nil ? "Add Medication" : "Update Medication")
                                .font(.soothing(.body))
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.medium)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            name.isEmpty ? theme.secondaryTextColor : theme.primaryColor,
                                            name.isEmpty ? theme.secondaryTextColor.opacity(0.8) : theme.primaryColor.opacity(0.8)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .disabled(name.isEmpty)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(medicationToEdit == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(theme.primaryColor)
                }
            }
            .background(theme.backgroundColor)
            .onAppear {
                setupInitialValues()
            }
            .alert("Validation Error", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private func setupInitialValues() {
        if let med = medicationToEdit {
            name = med.name ?? ""
            days = Int(med.days)
            foodTiming = med.foodTiming ?? "Before Food"
            stock = Int(med.stock)
            isStockManuallyEdited = true
            timesPerDay = Int(med.timesPerDay)
            isCritical = med.isCritical

            if let savedTimes = med.times, !savedTimes.isEmpty {
                times = savedTimes
            } else if let fallback = med.time {
                times = [fallback]
                timesPerDay = 1
            } else {
                times = generateDefaultTimes(count: timesPerDay)
            }
        } else {
            times = generateDefaultTimes(count: timesPerDay)
            stock = days * timesPerDay
        }
    }

    private func generateDefaultTimes(count: Int) -> [Date] {
        let calendar = Calendar.current
        let baseDate = Date()
        
        switch count {
        case 1:
            return [calendar.date(bySettingHour: 8, minute: 0, second: 0, of: baseDate) ?? baseDate]
        case 2:
            return [
                calendar.date(bySettingHour: 8, minute: 0, second: 0, of: baseDate) ?? baseDate,
                calendar.date(bySettingHour: 20, minute: 0, second: 0, of: baseDate) ?? baseDate
            ]
        case 3:
            return [
                calendar.date(bySettingHour: 8, minute: 0, second: 0, of: baseDate) ?? baseDate,
                calendar.date(bySettingHour: 14, minute: 0, second: 0, of: baseDate) ?? baseDate,
                calendar.date(bySettingHour: 20, minute: 0, second: 0, of: baseDate) ?? baseDate
            ]
        default:
            var defaultTimes: [Date] = []
            let interval = 24.0 / Double(count)
            for i in 0..<count {
                let hour = Int(8.0 + (Double(i) * interval)) % 24
                if let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: baseDate) {
                    defaultTimes.append(time)
                }
            }
            return defaultTimes.isEmpty ? Array(repeating: baseDate, count: count) : defaultTimes
        }
    }

    private func adjustTimesArray(to count: Int) {
        if count > times.count {
            let newTimes = generateDefaultTimes(count: count)
            for i in times.count..<count {
                if i < newTimes.count {
                    times.append(newTimes[i])
                } else {
                    times.append(Date())
                }
            }
        } else if count < times.count {
            times = Array(times.prefix(count))
        }
    }

    private func generateDoseLogs(for medication: Medication, in context: NSManagedObjectContext) {
        // Clear existing dose logs if editing
        if let existingLogs = medication.doseLog as? Set<DoseLog> {
            for log in existingLogs {
                context.delete(log)
            }
        }
        
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        
        for dayOffset in 0..<Int(medication.days) {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
            
            for time in medication.times ?? [] {
                let components = calendar.dateComponents([.hour, .minute], from: time)
                
                if let scheduledDate = calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: dayDate
                ) {
                    // Only create future doses or today's doses
                    if scheduledDate > Date() || calendar.isDate(scheduledDate, inSameDayAs: Date()) {
                        let dose = DoseLog(context: context)
                        dose.dateTime = scheduledDate
                        dose.isTaken = false
                        dose.medication = medication
                    }
                }
            }
        }
    }
    
    private func saveMedication() {
        // Validation
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Please enter a medication name"
            showingValidationAlert = true
            return
        }
        
        // Save using the main context instead of background context to avoid threading issues
        let medication: Medication
        
        if let existingMed = medicationToEdit {
            medication = existingMed
        } else {
            medication = Medication(context: viewContext)
        }
        
        // Set properties
        medication.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.days = Int16(days)
        medication.stock = Int16(stock)
        medication.foodTiming = foodTiming
        medication.time = times.first ?? Date()
        medication.timesPerDay = Int16(timesPerDay)
        medication.times = times
        medication.isCritical = isCritical
        
        if medicationToEdit == nil {
            medication.taken = false
        }
        
        // Generate dose logs
        generateDoseLogs(for: medication, in: viewContext)
        
        do {
            try viewContext.save()
            
            // Schedule notifications after successful save
            let id = medication.objectID.uriRepresentation().absoluteString
            NotificationManager.shared.scheduleNotifications(
                id: id,
                title: "Take \(name)",
                body: foodTiming,
                timesPerDay: times,
                numberOfDays: days,
                stock: Int(stock),
                isCritical: isCritical
            )
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            
        } catch {
            print("Failed to save medication: \(error.localizedDescription)")
            validationMessage = "Failed to save medication. Please try again."
            showingValidationAlert = true
        }
    }
}

// MARK: - Food Timing Chip
struct FoodTimingChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.theme) var theme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.soothing(.callout))
                .foregroundColor(isSelected ? .white : theme.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.round)
                        .fill(isSelected ? theme.accentColor : theme.secondaryBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.round)
                        .stroke(isSelected ? Color.clear : theme.secondaryColor.opacity(0.3), lineWidth: 1)
                )
        }
        .animation(.soothing, value: isSelected)
    }
}

#Preview {
    AddMedicationView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(\.theme, SoothingTheme())
}
