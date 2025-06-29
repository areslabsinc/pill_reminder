import SwiftUI
import CoreData

struct UpcomingTimelineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.theme) var theme

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Medication.name, ascending: true)],
        animation: .default)
    private var medications: FetchedResults<Medication>

    private let calendar = Calendar.current
    private let daysToShow = 7
    @State private var cachedDosesPerDay: [Date: [DoseLog]] = [:]
    @State private var isLoading = true
    @AppStorage("timelineRefreshNeeded") private var refreshNeeded = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(upcomingDates(), id: \.self) { date in
                    Section(header: sectionHeaderView(for: date)) {
                        let allDosesForDay = cachedDosesPerDay[calendar.startOfDay(for: date)] ?? []

                        if allDosesForDay.isEmpty {
                            Text("No medications scheduled")
                                .foregroundColor(theme.secondaryTextColor)
                                .font(.soothing(.body))
                                .padding(.vertical, 8)
                        } else {
                            ForEach(allDosesForDay, id: \.objectID) { dose in
                                if let medication = dose.medication {
                                    TimelineMedicationRow(
                                        dose: dose,
                                        medication: medication,
                                        isToday: calendar.isDateInToday(date),
                                        onTake: { markDoseTaken(dose) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Medication Timeline")
        .navigationBarTitleDisplayMode(.large)
        .listStyle(InsetGroupedListStyle())
        .onAppear {
            loadDoses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            loadDoses()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            // Handle time zone changes
            loadDoses()
        }
        .onChange(of: refreshNeeded) { _, _ in
            if refreshNeeded {
                loadDoses()
                refreshNeeded = false
            }
        }
        .refreshable {
            await refreshDoses()
        }
    }
    
    @ViewBuilder
    private func sectionHeaderView(for date: Date) -> some View {
        HStack {
            Text(sectionHeader(for: date))
                .font(.soothing(.headline))
                .foregroundColor(theme.textColor)
            
            Spacer()
            
            if !calendar.isDateInToday(date) {
                Text(shortDateFormat(date))
                    .font(.soothing(.caption))
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func upcomingDates() -> [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<daysToShow).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    private func sectionHeader(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        }
    }
    
    private func shortDateFormat(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func loadDoses() {
        isLoading = true
        
        // Perform loading on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            var newCache: [Date: [DoseLog]] = [:]
            
            for date in self.upcomingDates() {
                let startOfDay = self.calendar.startOfDay(for: date)
                let doses = self.allDosesFor(date: date)
                newCache[startOfDay] = doses
            }
            
            DispatchQueue.main.async {
                self.cachedDosesPerDay = newCache
                self.isLoading = false
            }
        }
    }
    
    @MainActor
    private func refreshDoses() async {
        isLoading = true
        
        await withCheckedContinuation { continuation in
            loadDoses()
            
            // Wait a bit for the loading to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }

    private func allDosesFor(date: Date) -> [DoseLog] {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        var allDoses: [DoseLog] = []
        
        // Use viewContext synchronously since we're already on background queue
        viewContext.performAndWait {
            for medication in medications {
                let doseLogs = (medication.doseLog as? Set<DoseLog>) ?? []
                let dosesForDay = doseLogs.filter {
                    guard let doseDate = $0.dateTime else { return false }
                    return doseDate >= startOfDay && doseDate < endOfDay
                }
                allDoses.append(contentsOf: dosesForDay)
            }
        }
        
        return allDoses.sorted {
            guard let date1 = $0.dateTime, let date2 = $1.dateTime else { return false }
            return date1 < date2
        }
    }
    
    private func markDoseTaken(_ dose: DoseLog) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        dose.isTaken = true
        if let medication = dose.medication, medication.stock > 0 {
            medication.stock -= 1
        }
        
        do {
            try viewContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            // Update badge count
            NotificationManager.shared.updateBadgeCount()
            
            // Reload the specific day
            if let doseDate = dose.dateTime {
                let startOfDay = calendar.startOfDay(for: doseDate)
                let doses = allDosesFor(date: doseDate)
                cachedDosesPerDay[startOfDay] = doses
            }
        } catch {
            print("Error marking dose as taken: \(error)")
            
            // Show error to user
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                let alert = UIAlertController(
                    title: "Error",
                    message: "Failed to mark dose as taken. Please try again.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                window.rootViewController?.present(alert, animated: true)
            }
        }
    }
}

// MARK: - Timeline Medication Row
struct TimelineMedicationRow: View {
    @ObservedObject var dose: DoseLog
    @ObservedObject var medication: Medication
    let isToday: Bool
    let onTake: () -> Void
    
    @Environment(\.theme) var theme
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Medication Info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(medication.name ?? "Unnamed")
                        .font(.soothing(.headline))
                        .foregroundColor(theme.textColor)
                        .lineLimit(1)
                    
                    if medication.isCritical {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(theme.errorColor)
                    }
                }

                if let doseTime = dose.dateTime {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text(formattedTime(from: doseTime))
                    }
                    .font(.soothing(.subheadline))
                    .foregroundColor(theme.secondaryTextColor)
                }

                HStack(spacing: Spacing.small) {
                    // Food timing badge
                    if let foodTiming = medication.foodTiming {
                        Label(foodTiming, systemImage: "fork.knife")
                            .font(.soothing(.caption))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.accentColor.opacity(0.2))
                            .cornerRadius(CornerRadius.small)
                    }
                    
                    // Stock warning
                    if medication.stock == 0 {
                        Label("Out of stock", systemImage: "exclamationmark.triangle.fill")
                            .font(.soothing(.caption))
                            .foregroundColor(theme.errorColor)
                    } else if medication.stock < 5 {
                        Label("\(medication.stock) left", systemImage: "pills.fill")
                            .font(.soothing(.caption))
                            .foregroundColor(theme.warningColor)
                    }
                }
            }

            Spacer()

            // Status/Action
            doseStatusView
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .animation(.soothing, value: dose.isTaken)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
    
    @ViewBuilder
    private var doseStatusView: some View {
        switch dose.timeStatus {
        case .taken:
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.successColor)
                    .font(.title2)
                Text("Taken")
                    .font(.soothing(.caption))
                    .foregroundColor(theme.successColor)
            }
            .transition(.scale.combined(with: .opacity))
            
        case .current where isToday && medication.stock > 0:
            Button(action: {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    onTake()
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "pills.circle.fill")
                        .font(.title2)
                    Text("Take")
                        .font(.soothing(.caption))
                }
                .foregroundColor(theme.primaryColor)
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
            .animation(.soothingSpring, value: isPressed)
            
        case .missed:
            VStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                    .foregroundColor(theme.errorColor)
                    .font(.title2)
                Text("Missed")
                    .font(.soothing(.caption))
                    .foregroundColor(theme.errorColor)
            }
            
        case .upcoming:
            VStack(spacing: 4) {
                Image(systemName: "clock.circle")
                    .foregroundColor(theme.warningColor)
                    .font(.title2)
                Text("Upcoming")
                    .font(.soothing(.caption))
                    .foregroundColor(theme.warningColor)
            }
            
        default:
            // For current status when stock is 0 or not today
            if medication.stock == 0 {
                VStack(spacing: 4) {
                    Image(systemName: "pills.circle")
                        .foregroundColor(theme.secondaryTextColor)
                        .font(.title2)
                    Text("No Stock")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.secondaryTextColor)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "clock.circle")
                        .foregroundColor(theme.warningColor)
                        .font(.title2)
                    Text("Pending")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.warningColor)
                }
            }
        }
    }
    
    private var accessibilityLabel: String {
        var label = medication.name ?? "Medication"
        
        if let doseTime = dose.dateTime {
            label += " at \(formattedTime(from: doseTime))"
        }
        
        switch dose.timeStatus {
        case .taken:
            label += ", taken"
        case .current:
            label += ", due now"
        case .missed:
            label += ", missed"
        case .upcoming:
            label += ", upcoming"
        case .unknown:
            break
        }
        
        if medication.stock == 0 {
            label += ", out of stock"
        } else if medication.stock < 5 {
            label += ", only \(medication.stock) pills remaining"
        }
        
        return label
    }
    
    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    private func isEligibleToTake() -> Bool {
        guard let scheduled = dose.dateTime, !dose.isTaken else { return false }
        let now = Date()
        return abs(scheduled.timeIntervalSince(now)) <= 7200
    }
    
    private func isPastDose() -> Bool {
        guard let scheduled = dose.dateTime else { return false }
        let now = Date()
        let calendar = Calendar.current
        
        if !calendar.isDate(scheduled, inSameDayAs: now) && scheduled < now {
            return true
        }
        
        if calendar.isDate(scheduled, inSameDayAs: now) {
            return now.timeIntervalSince(scheduled) > 7200
        }
        
        return false
    }
}

#Preview {
    NavigationView {
        UpcomingTimelineView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environment(\.theme, SoothingTheme())
    }
}
