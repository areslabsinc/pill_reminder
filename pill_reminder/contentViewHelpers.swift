import SwiftUI
import CoreData

// MARK: - Medication List View
struct MedicationListView: View {
    @Binding var editingMedication: Medication?
    @Binding var animatingMedicationID: NSManagedObjectID?
    @Binding var longPressedMedication: Medication?
    
    let medications: FetchedResults<Medication>
    let markNextEligibleDoseTaken: (Medication) -> Void
    let delete: (Medication) -> Void
    let refillStock: (Medication) -> Void
    let showSnoozeSheet: (Medication) -> Void
    let hasEligibleDoseToTake: (Medication) -> Bool
    let todayDoseLogs: (Medication) -> [DoseLog]
    
    @Environment(\.theme) var theme
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.medium) {
                ForEach(medications) { medication in
                    MedicationRowView(
                        medication: medication,
                        editingMedication: $editingMedication,
                        animatingMedicationID: $animatingMedicationID,
                        longPressedMedication: $longPressedMedication,
                        markNextEligibleDoseTaken: markNextEligibleDoseTaken,
                        delete: delete,
                        refillStock: refillStock,
                        showSnoozeSheet: showSnoozeSheet,
                        hasEligibleDoseToTake: hasEligibleDoseToTake,
                        todayDoseLogs: todayDoseLogs,
                        showHint: medication == medications.first && !UserDefaults.standard.bool(forKey: "hasSeenSwipeHint")
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Medication Row View
struct MedicationRowView: View {
    @ObservedObject var medication: Medication
    @Binding var editingMedication: Medication?
    @Binding var animatingMedicationID: NSManagedObjectID?
    @Binding var longPressedMedication: Medication?
    
    let markNextEligibleDoseTaken: (Medication) -> Void
    let delete: (Medication) -> Void
    let refillStock: (Medication) -> Void
    let showSnoozeSheet: (Medication) -> Void
    let hasEligibleDoseToTake: (Medication) -> Bool
    let todayDoseLogs: (Medication) -> [DoseLog]
    let showHint: Bool
    
    @Environment(\.theme) var theme
    
    var body: some View {
        ZStack(alignment: .leading) {
            SwipeableCard(
                content: {
                    MedicationCard(
                        medication: medication,
                        onEdit: { editingMedication = medication },
                        onTake: { markNextEligibleDoseTaken(medication) },
                        onDelete: { delete(medication) },
                        onRefill: { refillStock(medication) },
                        isAnimating: animatingMedicationID == medication.objectID,
                        todayDoseLogs: todayDoseLogs(medication)
                    )
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        longPressedMedication = medication
                    }
                },
                leadingActions: leadingSwipeActions,
                trailingActions: trailingSwipeActions
            )
            .slideAndFade(isVisible: true)
            
            if showHint {
                SwipeHintOverlay(direction: .leading)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var leadingSwipeActions: [SwipeAction] {
        guard hasEligibleDoseToTake(medication) && medication.stock > 0 else { return [] }
        
        return [
            SwipeAction(
                icon: "checkmark.circle.fill",
                title: "Take",
                color: theme.successColor,
                action: { markNextEligibleDoseTaken(medication) }
            )
        ]
    }
    
    private var trailingSwipeActions: [SwipeAction] {
        [
            SwipeAction(
                icon: "pencil.circle.fill",
                title: "Edit",
                color: theme.primaryColor,
                action: { editingMedication = medication }
            ),
            SwipeAction(
                icon: "plus.circle.fill",
                title: "Refill",
                color: theme.successColor,
                action: { refillStock(medication) }
            ),
            SwipeAction(
                icon: "clock.fill",
                title: "Snooze",
                color: theme.warningColor,
                action: { showSnoozeSheet(medication) }
            )
        ]
    }
}

// MARK: - Navigation Toolbar
struct NavigationToolbar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack {
            NavigationLink(destination: UpcomingTimelineView().environment(\.theme, theme)) {
                Label("Timeline", systemImage: "calendar")
                    .foregroundColor(theme.primaryColor)
            }
            
            Spacer()
            
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
            }
        }
    }
}

// MARK: - Info Badge Component
struct InfoBadge: View {
    let icon: String
    let text: String
    let color: Color
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.soothing(.caption))
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .cornerRadius(CornerRadius.small)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dose Pills Row
struct DosePillsRow: View {
    let medication: Medication
    let todayDoses: [DoseLog]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.small) {
                ForEach(Array(todayDoses.enumerated()), id: \.offset) { index, dose in
                    DosePill(dose: dose, index: index)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's doses")
    }
}

// MARK: - Take Now Button
struct TakeNowButton: View {
    @Binding var isPressed: Bool
    let action: () -> Void
    @Environment(\.theme) var theme
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                action()
            }
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                Text("Take Now")
                    .font(.soothing(.body))
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body)
            }
            .foregroundColor(.white)
            .padding(Spacing.medium + 4)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        theme.primaryColor,
                        theme.primaryColor.opacity(0.8)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(CornerRadius.medium)
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.soothingSpring, value: isPressed)
        .accessibilityLabel("Take medication now")
        .accessibilityHint("Double tap to mark this dose as taken")
    }
}

// MARK: - Dose Pill View
struct DosePill: View {
    let dose: DoseLog
    let index: Int
    @Environment(\.theme) var theme
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Capsule()
                    .fill(pillColor)
                    .frame(width: 30, height: 45)
                
                if dose.isTaken {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            
            if let doseTime = dose.dateTime {
                Text(formattedTime(from: doseTime))
                    .font(.soothing(.caption2))
                    .foregroundColor(theme.secondaryTextColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
    
    private var pillColor: Color {
        switch dose.timeStatus {
        case .taken:
            return theme.successColor
        case .missed:
            return theme.errorColor
        case .current:
            return theme.warningColor
        case .upcoming:
            return theme.secondaryColor
        case .unknown:
            return theme.secondaryTextColor
        }
    }
    
    private var accessibilityLabel: String {
        guard let doseTime = dose.dateTime else { return "Dose \(index + 1)" }
        let timeString = formattedTime(from: doseTime)
        
        switch dose.timeStatus {
        case .taken:
            return "Dose at \(timeString) taken"
        case .missed:
            return "Dose at \(timeString) missed"
        case .current:
            return "Dose at \(timeString) due now"
        case .upcoming:
            return "Dose at \(timeString) upcoming"
        case .unknown:
            return "Dose at \(timeString)"
        }
    }
    
    private func formattedTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
