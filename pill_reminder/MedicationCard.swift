import SwiftUI
import CoreData

// MARK: - Medication Card View
struct MedicationCard: View {
    @ObservedObject var medication: Medication
    let onEdit: () -> Void
    let onTake: () -> Void
    let onDelete: () -> Void
    let onRefill: () -> Void
    let isAnimating: Bool
    let todayDoseLogs: [DoseLog]
    
    @Environment(\.theme) var theme
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header with name and critical indicator
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(medication.name ?? "Unnamed Medication")
                            .font(.soothing(.headline))
                            .foregroundColor(theme.textColor)
                            .lineLimit(1)
                        
                        if medication.isCritical == true {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(theme.errorColor)
                                .transition(.scale)
                        }
                    }
                    
                    Text("\(medication.days) days • \(medication.timesPerDay)x daily")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.secondaryTextColor)
                }
                
                Spacer()
                
                // Stock indicator
                stockBadge
            }
            
            // Food timing
            if let foodTiming = medication.foodTiming {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.caption2)
                    Text(foodTiming)
                        .font(.soothing(.caption))
                }
                .foregroundColor(theme.accentColor)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, 4)
                .background(theme.accentColor.opacity(0.2))
                .cornerRadius(CornerRadius.small)
            }
            
            // Today's doses
            if !todayDoseLogs.isEmpty {
                DosePillsRow(medication: medication, todayDoses: todayDoseLogs)
            }
            
            // Take button if eligible
            if hasEligibleDoseToTake() && medication.stock > 0 {
                TakeNowButton(isPressed: $isPressed, action: onTake)
                    .disabled(isAnimating)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .fill(theme.backgroundColor)
                .shadow(
                    color: theme.shadowColor,
                    radius: isAnimating ? 12 : 8,
                    x: 0,
                    y: isAnimating ? 6 : 4
                )
        )
        .scaleEffect(isAnimating ? 1.02 : 1.0)
        .animation(.soothingSpring, value: isAnimating)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var stockBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "pills.fill")
                .font(.caption)
            
            if medication.stock > 0 {
                Text("\(medication.stock)")
                    .font(.soothing(.caption))
                    .fontWeight(.medium)
            } else {
                Text("Empty")
                    .font(.soothing(.caption))
                    .fontWeight(.medium)
            }
        }
        .foregroundColor(stockColor)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, 4)
        .background(stockColor.opacity(0.2))
        .cornerRadius(CornerRadius.small)
    }
    
    private var stockColor: Color {
        if medication.stock == 0 {
            return theme.errorColor
        } else if medication.stock < 5 {
            return theme.warningColor
        } else {
            return theme.successColor
        }
    }
    
    private func hasEligibleDoseToTake() -> Bool {
        let now = Date()
        for dose in todayDoseLogs {
            if !dose.isTaken, let scheduled = dose.dateTime {
                let timeInterval = scheduled.timeIntervalSince(now)
                if timeInterval > -7200 && timeInterval < 7200 {
                    return true
                }
            }
        }
        return false
    }
}
