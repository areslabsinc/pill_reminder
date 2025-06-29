import SwiftUI
import CoreData

// MARK: - Undo Action Type
enum UndoActionType {
    case medicationTaken(medication: Medication, dose: DoseLog, previousStock: Int16)
    case medicationDeleted(medicationData: DeletedMedicationData)
    
    var title: String {
        switch self {
        case .medicationTaken(let medication, _, _):
            return "\(medication.name ?? "Medication") marked as taken"
        case .medicationDeleted(let data):
            return "\(data.name) deleted"
        }
    }
    
    var icon: String {
        switch self {
        case .medicationTaken:
            return "checkmark.circle.fill"
        case .medicationDeleted:
            return "trash.fill"
        }
    }
}

// MARK: - Deleted Medication Data
struct DeletedMedicationData {
    let name: String
    let days: Int16
    let stock: Int16
    let foodTiming: String
    let time: Date
    let timesPerDay: Int16
    let times: [Date]
    let isCritical: Bool // Added to preserve critical status
}

// MARK: - Undo Manager
class UndoManager: ObservableObject {
    @Published var currentUndo: UndoActionType?
    @Published var isShowingUndo = false
    
    private var undoTimer: Timer?
    private let undoDuration: TimeInterval = 5.0
    
    func showUndo(_ action: UndoActionType) {
        // Cancel any existing timer
        undoTimer?.invalidate()
        
        // Update state
        currentUndo = action
        withAnimation(.soothing) {
            isShowingUndo = true
        }
        
        // Start new timer
        undoTimer = Timer.scheduledTimer(withTimeInterval: undoDuration, repeats: false) { [weak self] _ in
            self?.hideUndo()
        }
    }
    
    func performUndo(in context: NSManagedObjectContext) {
        guard let action = currentUndo else { return }
        
        switch action {
        case .medicationTaken(let medication, let dose, let previousStock):
            // Revert dose taken
            dose.isTaken = false
            medication.stock = previousStock
            
            // Update notification badge
            NotificationManager.shared.updateBadgeCount()
            
        case .medicationDeleted(let data):
            // Recreate medication
            let medication = Medication(context: context)
            medication.name = data.name
            medication.days = data.days
            medication.stock = data.stock
            medication.foodTiming = data.foodTiming
            medication.time = data.time
            medication.timesPerDay = data.timesPerDay
            medication.times = data.times
            medication.taken = false
            medication.isCritical = data.isCritical // Restore critical status
            
            // Recreate dose logs
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            
            for dayOffset in 0..<Int(data.days) {
                guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { continue }
                
                for time in data.times {
                    let components = calendar.dateComponents([.hour, .minute], from: time)
                    
                    if let scheduledDate = calendar.date(
                        bySettingHour: components.hour ?? 0,
                        minute: components.minute ?? 0,
                        second: 0,
                        of: dayDate
                    ) {
                        if scheduledDate > Date() || calendar.isDate(scheduledDate, inSameDayAs: Date()) {
                            let dose = DoseLog(context: context)
                            dose.dateTime = scheduledDate
                            dose.isTaken = false
                            dose.medication = medication
                        }
                    }
                }
            }
            
            // Reschedule notifications
            let id = medication.objectID.uriRepresentation().absoluteString
            NotificationManager.shared.scheduleNotifications(
                id: id,
                title: "Take \(data.name)",
                body: data.foodTiming,
                timesPerDay: data.times,
                numberOfDays: Int(data.days),
                stock: Int(data.stock),
                isCritical: data.isCritical
            )
        }
        
        do {
            try context.save()
            hideUndo()
            
            // Haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            print("Error performing undo: \(error)")
        }
    }
    
    func hideUndo() {
        undoTimer?.invalidate()
        undoTimer = nil
        
        withAnimation(.soothing) {
            isShowingUndo = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentUndo = nil
        }
    }
    
    deinit {
        undoTimer?.invalidate()
    }
}

// MARK: - Undo Banner View
struct UndoBanner: View {
    @ObservedObject var undoManager: UndoManager
    let onUndo: () -> Void
    
    @Environment(\.theme) var theme
    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        if undoManager.isShowingUndo, let action = undoManager.currentUndo {
            HStack(spacing: Spacing.medium) {
                // Icon
                Image(systemName: action.icon)
                    .font(.title3)
                    .foregroundColor(theme.backgroundColor)
                
                // Message
                Text(action.title)
                    .font(.soothing(.callout))
                    .foregroundColor(theme.backgroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                // Undo button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onUndo()
                }) {
                    Text("Undo")
                        .font(.soothing(.callout))
                        .fontWeight(.medium)
                        .foregroundColor(theme.textColor)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.small)
                        .background(
                            Capsule()
                                .fill(theme.backgroundColor)
                        )
                }
                
                // Close button
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    undoManager.hideUndo()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(theme.backgroundColor.opacity(0.8))
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(
                Capsule()
                    .fill(theme.textColor)
                    .shadow(color: theme.shadowColor, radius: 10, y: 5)
            )
            .padding(.horizontal, Spacing.medium)
            .offset(y: dragOffset)
            .opacity(opacity)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height
                            opacity = 1.0 + (value.translation.height / 100.0)
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -50 {
                            undoManager.hideUndo()
                        } else {
                            withAnimation(.soothingSpring) {
                                dragOffset = 0
                                opacity = 1.0
                            }
                        }
                    }
            )
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .animation(.soothingSpring, value: undoManager.isShowingUndo)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Undo \(action.title)")
            .accessibilityHint("Double tap to undo, or swipe up to dismiss")
        }
    }
}

// MARK: - View Extension for Undo
extension View {
    func undoBanner(undoManager: UndoManager, onUndo: @escaping () -> Void) -> some View {
        overlay(
            VStack {
                UndoBanner(undoManager: undoManager, onUndo: onUndo)
                    .padding(.top, 50) // Account for status bar
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(undoManager.isShowingUndo) // Only allow hits when showing
        )
    }
}
