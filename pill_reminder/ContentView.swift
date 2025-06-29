import SwiftUI
import CoreData
import UserNotifications

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.theme) var theme
    @EnvironmentObject var themeManager: ThemeManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Medication.time, ascending: true)],
        animation: .default)
    private var medications: FetchedResults<Medication>

    @State private var showingAddMedication = false
    @State private var editingMedication: Medication? = nil
    @State private var showPillAnimation = false
    @State private var animatingMedicationID: NSManagedObjectID? = nil
    @State private var snoozeSheetMedication: Medication? = nil
    @StateObject private var contentUndoManager = ContentUndoManager()
    @State private var longPressedMedication: Medication? = nil
    @State private var showDeleteConfirmation = false
    @State private var medicationToDelete: Medication? = nil
    @State private var errorMessage: String? = nil
    @State private var showError = false
    
    // Improved cache management
    @StateObject private var doseLogCache = DoseLogCache()

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationView {
                mainContent
                    
                // Detail view placeholder for iPad
                VStack {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 80))
                        .foregroundColor(theme.secondaryColor.opacity(0.3))
                    Text("Select a medication")
                        .font(.soothing(.title3))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
            .overlay(pillAnimationOverlay)
            .undoBanner(undoManager: contentUndoManager) {
                contentUndoManager.performUndo(in: viewContext)
            }
        } else {
            NavigationView {
                mainContent
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .overlay(pillAnimationOverlay)
            .undoBanner(undoManager: contentUndoManager) {
                contentUndoManager.performUndo(in: viewContext)
            }
        }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        ZStack {
                backgroundView
                
                if medications.isEmpty {
                    emptyStateView
                } else {
                    medicationListView
                }
                
                floatingActionButton
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: UpcomingTimelineView().environment(\.theme, theme)) {
                        Label("Timeline", systemImage: "calendar")
                            .foregroundColor(theme.primaryColor)
                            .accessibilityLabel("View medication timeline")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    themeMenu
                }
            }
        .sheet(item: $editingMedication) { medication in
            AddMedicationView(medicationToEdit: medication)
                .environment(\.managedObjectContext, viewContext)
                .environment(\.theme, theme)
        }
        .sheet(isPresented: $showingAddMedication) {
            AddMedicationView()
                .environment(\.managedObjectContext, viewContext)
                .environment(\.theme, theme)
        }
        .sheet(item: $snoozeSheetMedication) { medication in
            SnoozeOptionsSheet(
                medication: medication,
                onSnooze: { minutes in
                    snoozeReminder(for: medication, minutes: minutes)
                }
            )
            .presentationDetents([.height(400)])
            .environment(\.theme, theme)
        }
        .confirmationDialog(
            "Medication Options",
            isPresented: .constant(longPressedMedication != nil),
            presenting: longPressedMedication
        ) { medication in
            medicationOptionsButtons(for: medication)
        } message: { medication in
            Text(medication.name ?? "Medication")
        }
        .alert("Delete Medication?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                medicationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let medication = medicationToDelete {
                    delete(medication: medication)
                }
            }
        } message: {
            if let medication = medicationToDelete {
                Text("Are you sure you want to delete \(medication.name ?? "this medication")? This action cannot be undone.")
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            doseLogCache.updateCache(for: medications)
            
            // Check critical doses on launch
            PersistentAlertHandler.shared.checkAllCriticalDosesOnLaunch(context: viewContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
            doseLogCache.updateCache(for: medications)
        }
        .onReceive(NotificationCenter.default.publisher(for: .medicationTaken)) { notification in
            handleMedicationTakenNotification(notification)
        }
        .onDisappear {
            doseLogCache.clearCache()
        }
    }
    
    private var backgroundView: some View {
        theme.backgroundColor
            .ignoresSafeArea(.all)
    }
    
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "pills.fill",
            title: "No Medications Yet",
            subtitle: "Add your first medication to start your health journey",
            actionTitle: "Add Medication",
            action: { showingAddMedication = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var medicationListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(medications) { medication in
                    medicationRow(for: medication)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 100) // Space for floating action button
        }
    }
    
    @ViewBuilder
    private func medicationRow(for medication: Medication) -> some View {
        MedicationRowView(
            medication: medication,
            editingMedication: $editingMedication,
            animatingMedicationID: $animatingMedicationID,
            longPressedMedication: $longPressedMedication,
            markNextEligibleDoseTaken: markNextEligibleDoseTaken,
            delete: { medicationToDelete = $0; showDeleteConfirmation = true },
            refillStock: refillStock,
            showSnoozeSheet: showSnoozeSheet,
            hasEligibleDoseToTake: hasEligibleDoseToTake,
            todayDoseLogs: { doseLogCache.getDoseLogs(for: $0) },
            showHint: medication == medications.first && !UserDefaults.standard.bool(forKey: "hasSeenSwipeHint")
        )
    }
    
    private var floatingActionButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton(icon: "plus") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAddMedication = true
                }
                .padding(Spacing.large)
                .accessibilityLabel("Add new medication")
            }
        }
    }
    
    private var pillAnimationOverlay: some View {
        Group {
            if showPillAnimation {
                PillTakingAnimation {
                    showPillAnimation = false
                    animatingMedicationID = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
                .ignoresSafeArea()
                .soothingTransition()
            }
        }
    }
    
    private var themeMenu: some View {
        Menu {
            ForEach(themeManager.availableThemes, id: \.name) { theme in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    themeManager.setTheme(theme)
                }) {
                    Label(theme.name, systemImage: themeManager.currentTheme.name == theme.name ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Image(systemName: "paintbrush.fill")
                .foregroundColor(theme.primaryColor)
                .accessibilityLabel("Change theme")
        }
    }
    
    @ViewBuilder
    private func medicationOptionsButtons(for medication: Medication) -> some View {
        Button {
            editingMedication = medication
            longPressedMedication = nil
        } label: {
            Label("Edit Medication", systemImage: "pencil.circle.fill")
        }
        
        Button {
            refillStock(for: medication)
            longPressedMedication = nil
        } label: {
            Label("Refill Stock", systemImage: "plus.circle.fill")
        }
        
        Button(role: .destructive) {
            medicationToDelete = medication
            showDeleteConfirmation = true
            longPressedMedication = nil
        } label: {
            Label("Delete Medication", systemImage: "trash.circle.fill")
        }
        
        Button("Cancel", role: .cancel) {
            longPressedMedication = nil
        }
    }

    // MARK: - Helper Functions
    
    private func handleMedicationTakenNotification(_ notification: Notification) {
        guard let medicationId = notification.userInfo?["medicationId"] as? String else { return }
        
        viewContext.perform {
            // Find medication by ID
            if let medication = medications.first(where: { $0.objectID.uriRepresentation().absoluteString == medicationId }) {
                // Find and mark the appropriate dose
                if hasEligibleDoseToTake(for: medication) {
                    markNextEligibleDoseTaken(for: medication)
                }
            }
        }
    }
    
    func showSnoozeSheet(for medication: Medication) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        snoozeSheetMedication = medication
    }
    
    func snoozeReminder(for medication: Medication, minutes: Int) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        let id = medication.objectID.uriRepresentation().absoluteString
        NotificationManager.shared.cancelNotifications(for: id)
        
        let content = UNMutableNotificationContent()
        content.title = "Time to take \(medication.name ?? "your medication")"
        content.body = medication.foodTiming ?? "Don't forget your medication"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "\(id)_snooze", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling snooze notification: \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to snooze reminder"
                    self.showError = true
                }
            }
        }
    }

    func todayDoseLogs(for medication: Medication) -> [DoseLog] {
        return doseLogCache.getDoseLogs(for: medication)
    }
    
    func hasEligibleDoseToTake(for medication: Medication) -> Bool {
        let now = Date()
        for dose in doseLogCache.getDoseLogs(for: medication) {
            if !dose.isTaken, let scheduled = dose.dateTime {
                let timeInterval = scheduled.timeIntervalSince(now)
                if timeInterval > -7200 && timeInterval < 7200 {
                    return true
                }
            }
        }
        return false
    }

    func markNextEligibleDoseTaken(for medication: Medication) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        animatingMedicationID = medication.objectID
        showPillAnimation = true
        
        let now = Date()
        var takenDose: DoseLog?
        let previousStock = medication.stock
        
        for dose in doseLogCache.getDoseLogs(for: medication) {
            if !dose.isTaken, let scheduled = dose.dateTime {
                let timeInterval = scheduled.timeIntervalSince(now)
                
                if timeInterval > -7200 && timeInterval < 7200 {
                    dose.isTaken = true
                    takenDose = dose
                    if medication.stock > 0 {
                        medication.stock -= 1
                    }
                    
                    // Cancel persistent monitoring for this dose if critical
                    if medication.isCritical {
                        let medicationId = medication.objectID.uriRepresentation().absoluteString
                        if let encodedId = medicationId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                            let doseIdentifier = "\(encodedId)_\(scheduled.timeIntervalSince1970)"
                            
                            // Stop persistent monitoring
                            PersistentAlertHandler.shared.stopMonitoring(doseIdentifier: doseIdentifier)
                            
                            // Cancel any follow-up notifications for this specific dose
                            NotificationManager.shared.cancelFollowUpsForDose(doseIdentifier)
                        }
                    }
                    
                    do {
                        try viewContext.save()
                        
                        if let dose = takenDose {
                            contentUndoManager.showUndo(.medicationTaken(
                                medication: medication,
                                dose: dose,
                                previousStock: previousStock
                            ))
                        }
                        
                        // Update cache
                        doseLogCache.updateCache(for: medications)
                        
                        // Update notification badge
                        NotificationManager.shared.updateBadgeCount()
                        
                    } catch {
                        print("Error saving dose taken: \(error)")
                        errorMessage = "Failed to mark medication as taken"
                        showError = true
                    }
                    break
                }
            }
        }
        
        if takenDose == nil {
            // Reset animation states since nothing was actually taken
            animatingMedicationID = nil
            showPillAnimation = false
            
            // Show appropriate error message
            errorMessage = "This dose can only be taken within 2 hours of its scheduled time"
            showError = true
        }
    }

    private func refillStock(for medication: Medication) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let doseLogs = (medication.doseLog as? Set<DoseLog>) ?? []
        let sortedDoses = doseLogs.sorted {
            ($0.dateTime ?? Date.distantPast) < ($1.dateTime ?? Date.distantPast)
        }
        
        if let firstDose = sortedDoses.first, let startDate = firstDose.dateTime {
            let daysElapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: today).day ?? 0
            let daysRemaining = max(0, Int(medication.days) - daysElapsed)
            let neededStock = daysRemaining * Int(medication.timesPerDay)
            
            medication.stock = Int16(max(0, neededStock))
            
            do {
                try viewContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                doseLogCache.updateCache(for: medications)
                
                // Show success feedback
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    let feedbackView = UIView(frame: CGRect(x: 0, y: -100, width: window.frame.width, height: 100))
                    feedbackView.backgroundColor = UIColor(theme.successColor)
                    
                    let label = UILabel(frame: feedbackView.bounds)
                    label.text = "Stock refilled successfully"
                    label.textColor = .white
                    label.textAlignment = .center
                    label.font = .systemFont(ofSize: 16, weight: .medium)
                    feedbackView.addSubview(label)
                    
                    window.addSubview(feedbackView)
                    
                    UIView.animate(withDuration: 0.3, animations: {
                        feedbackView.frame.origin.y = 0
                    }) { _ in
                        UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                            feedbackView.frame.origin.y = -100
                        }) { _ in
                            feedbackView.removeFromSuperview()
                        }
                    }
                }
            } catch {
                print("Error refilling stock: \(error)")
                errorMessage = "Failed to refill stock"
                showError = true
            }
        }
    }
    
    private func delete(medication: Medication) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        let deletedData = DeletedMedicationData(
            name: medication.name ?? "Unnamed",
            days: medication.days,
            stock: medication.stock,
            foodTiming: medication.foodTiming ?? "No Preference",
            time: medication.time ?? Date(),
            timesPerDay: medication.timesPerDay,
            times: medication.times ?? [],
            isCritical: medication.isCritical
        )
        
        withAnimation {
            let id = medication.objectID.uriRepresentation().absoluteString
            
            // Cancel all notifications
            NotificationManager.shared.cancelNotifications(for: id)
            
            // Cancel any pending follow-up checks
            medication.cleanupPendingFollowUps()
            
            // Clean up UserDefaults for critical medication flag
            medication.cleanupUserDefaults()
            
            // Delete all dose logs
            if let doseLogs = medication.doseLog as? Set<DoseLog> {
                for dose in doseLogs {
                    viewContext.delete(dose)
                }
            }
            
            // Delete the medication
            viewContext.delete(medication)
            
            do {
                try viewContext.save()
                contentUndoManager.showUndo(.medicationDeleted(medicationData: deletedData))
                doseLogCache.updateCache(for: medications)
                medicationToDelete = nil
            } catch {
                print("Error deleting medication: \(error)")
                errorMessage = "Failed to delete medication"
                showError = true
            }
        }
    }
}

// MARK: - Dose Log Cache
class DoseLogCache: ObservableObject {
    @Published private var cache: [NSManagedObjectID: [DoseLog]] = [:]
    private let queue = DispatchQueue(label: "com.pillreminder.dosecache", attributes: .concurrent)
    
    func getDoseLogs(for medication: Medication) -> [DoseLog] {
        queue.sync {
            return cache[medication.objectID] ?? []
        }
    }
    
    func updateCache(for medications: FetchedResults<Medication>) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            var newCache: [NSManagedObjectID: [DoseLog]] = [:]
            
            for medication in medications {
                newCache[medication.objectID] = self.todayDoseLogs(for: medication)
            }
            
            DispatchQueue.main.async {
                self.cache = newCache
            }
        }
    }
    
    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
    
    private func todayDoseLogs(for medication: Medication) -> [DoseLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let doseLogs = (medication.doseLog as? Set<DoseLog>) ?? []
        
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
}

// MARK: - Content Undo Manager
class ContentUndoManager: UndoManager {
    // Inherits all functionality from UndoManager
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(\.theme, SoothingTheme())
        .environmentObject(ThemeManager.shared)
}
