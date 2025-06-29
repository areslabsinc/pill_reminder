//
//  CriticalMedicationIndicator.swift
//  pill_reminder
//
//  Created by Akash Lakshmipathy on 29/06/25.
//

import SwiftUI

// MARK: - Critical Medication Indicator
struct CriticalMedicationIndicator: View {
    let medication: Medication
    let hasOverdueDose: Bool
    
    @State private var isPulsing = false
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: hasOverdueDose ? 16 : 14))
                .foregroundColor(hasOverdueDose ? .white : theme.errorColor)
            
            if hasOverdueDose {
                Text("CRITICAL")
                    .font(.soothing(.caption))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, hasOverdueDose ? 8 : 4)
        .padding(.vertical, hasOverdueDose ? 4 : 2)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .fill(hasOverdueDose ? theme.errorColor : theme.errorColor.opacity(0.15))
        )
        .scaleEffect(hasOverdueDose && isPulsing ? 1.1 : 1.0)
        .animation(
            hasOverdueDose ? Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
            value: isPulsing
        )
        .onAppear {
            if hasOverdueDose {
                isPulsing = true
            }
        }
    }
}

// MARK: - Persistent Alert Status View
struct PersistentAlertStatusView: View {
    let medication: Medication
    @State private var overdueCount = 0
    @State private var nextAlertTime: Date?
    
    @Environment(\.theme) var theme
    
    var body: some View {
        if medication.isCritical && overdueCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(theme.errorColor)
                    
                    Text("Persistent alerts active")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.errorColor)
                    
                    Spacer()
                    
                    if let nextTime = nextAlertTime {
                        Text("Next: \(relativeTime(from: nextTime))")
                            .font(.soothing(.caption2))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                }
                
                if overdueCount > 1 {
                    Text("\(overdueCount) doses need attention")
                        .font(.soothing(.caption2))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(theme.errorColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(theme.errorColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .onAppear {
                updateAlertStatus()
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                updateAlertStatus()
            }
        }
    }
    
    private func updateAlertStatus() {
        let overdueDoses = medication.todayDoses.filter { dose in
            guard !dose.isTaken,
                  let doseTime = dose.dateTime else { return false }
            
            let timeSince = Date().timeIntervalSince(doseTime)
            return timeSince > 0 && timeSince < 7200 // Overdue but within window
        }
        
        overdueCount = overdueDoses.count
        
        // Calculate next alert time
        if overdueCount > 0 {
            // Next alert in 30 minutes
            nextAlertTime = Date().addingTimeInterval(1800)
        } else {
            nextAlertTime = nil
        }
    }
    
    private func relativeTime(from date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 60 {
            return "< 1 min"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours) hr"
        }
    }
}

// MARK: - Update MedicationCard to include persistent alert status
extension MedicationCard {
    var hasOverdueCriticalDose: Bool {
        guard medication.isCritical else { return false }
        
        return todayDoseLogs.contains { dose in
            guard !dose.isTaken,
                  let doseTime = dose.dateTime else { return false }
            
            let timeSince = Date().timeIntervalSince(doseTime)
            return timeSince > 0 && timeSince < 7200
        }
    }
}

// MARK: - Critical Medication Settings View
struct CriticalMedicationSettingsView: View {
    @Binding var isCritical: Bool
    @State private var showInfo = false
    
    @Environment(\.theme) var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    
                    Spacer()
                    
                    Button(action: { showInfo.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(theme.primaryColor)
                    }
                }
            }
            .tint(theme.errorColor)
            
            if showInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are persistent alerts?")
                        .font(.soothing(.caption))
                        .fontWeight(.medium)
                        .foregroundColor(theme.textColor)
                    
                    Text("For critical medications, you'll receive:")
                        .font(.soothing(.caption))
                        .foregroundColor(theme.secondaryTextColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Initial reminder at scheduled time", systemImage: "1.circle.fill")
                        Label("Follow-up after 30 minutes if not taken", systemImage: "2.circle.fill")
                        Label("Urgent alert after 1 hour", systemImage: "3.circle.fill")
                        Label("Critical alert after 2 hours", systemImage: "4.circle.fill")
                    }
                    .font(.soothing(.caption2))
                    .foregroundColor(theme.secondaryTextColor)
                    
                    Text("Alerts stop automatically when you mark the dose as taken.")
                        .font(.soothing(.caption2))
                        .foregroundColor(theme.secondaryTextColor)
                        .italic()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .fill(theme.secondaryBackgroundColor)
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.soothing, value: showInfo)
    }
}
