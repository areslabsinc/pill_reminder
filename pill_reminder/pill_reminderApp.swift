//
//  pill_reminderApp.swift
//  pill_reminder
//
//  Created by Akash Lakshmipathy on 11/06/25.
//

import SwiftUI
import CoreData

@main
struct pill_reminderApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showLaunchScreen = true
    @Environment(\.colorScheme) var colorScheme

    init() {
        // Register transformers BEFORE creating persistence controller
        ValueTransformer.setValueTransformer(
            DateArrayTransformer(),
            forName: NSValueTransformerName("DateArrayTransformer")
        )
        
        ValueTransformer.setValueTransformer(
            StringArrayTransformer(),
            forName: NSValueTransformerName("StringArrayTransformer")
        )
        
        // Initialize notification manager with enhanced setup
        NotificationManager.shared.requestAuthorization()
        configureInitialNavigationBarAppearance()
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // Setup notification categories for actions
        NotificationManager.shared.setupNotificationCategories()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environment(\.theme, themeManager.currentTheme)
                    .environmentObject(themeManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        // Clear badge when app becomes active
                        UNUserNotificationCenter.current().setBadgeCount(0)
                        
                        // Perform maintenance
                        NotificationManager.shared.performMaintenance()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                        // Cancel all pending work items when app terminates
                        NotificationManager.shared.cancelAllPendingFollowUps()
                        PersistentAlertHandler.shared.stopAllMonitoring()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .notificationTapped)) { notification in
                        // Handle notification tap
                        if notification.userInfo?["medicationId"] != nil {
                            // TODO: Navigate to medication or handle action
                            // This will be implemented when navigation to specific medication is added
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        // App entering background - persistent monitoring will continue
                        print("App entering background, persistent alerts will continue")
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                        // App returning to foreground - refresh critical dose status
                        checkForPendingFollowUps()
                    }
                    .onChange(of: colorScheme) { _, _ in
                        // Update navigation bar when color scheme changes
                        configureNavigationBarAppearance(for: themeManager.currentTheme, colorScheme: colorScheme)
                    }
                    .onReceive(themeManager.objectWillChange) { _ in
                        // Update navigation bar when theme changes
                        configureNavigationBarAppearance(for: themeManager.currentTheme, colorScheme: colorScheme)
                    }
                
                // Launch screen overlay
                if showLaunchScreen {
                    LaunchScreen()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Configure navigation bar with current theme and color scheme
                configureNavigationBarAppearance(for: themeManager.currentTheme, colorScheme: colorScheme)
                
                // Hide launch screen after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showLaunchScreen = false
                    }
                }
                
                // Check for medications that need follow-up reminders
                checkForPendingFollowUps()
                
                // Perform initial maintenance
                NotificationManager.shared.performMaintenance()
            }
        }
    }
    
    private func checkForPendingFollowUps() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<Medication> = Medication.fetchRequest()
        
        do {
            let medications = try context.fetch(fetchRequest)
            
            // Check all medications for follow-up needs
            for medication in medications {
                medication.checkForFollowUpReminders()
                
                // Start persistent monitoring for critical medications
                if medication.isCritical {
                    medication.startPersistentMonitoring(context: context)
                }
            }
            
            // Also check all critical doses on app launch
            PersistentAlertHandler.shared.checkAllCriticalDosesOnLaunch(context: context)
            
        } catch {
            print("Error checking for follow-up reminders: \(error)")
        }
    }
    
    // MARK: - Navigation Bar Configuration
    
    private func configureInitialNavigationBarAppearance() {
        // Set a basic configuration that will be updated later
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    private func configureNavigationBarAppearance(for theme: Theme, colorScheme: ColorScheme) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        // Use theme background color that adapts to light/dark mode
        appearance.backgroundColor = UIColor(theme.backgroundColor)
        
        // Configure title colors using theme text colors
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(theme.textColor),
            .font: UIFont.rounded(ofSize: 20, weight: .medium)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(theme.textColor),
            .font: UIFont.rounded(ofSize: 34, weight: .medium)
        ]
        
        // Remove shadow for cleaner look, but add subtle border if needed
        appearance.shadowColor = .clear
        
        // Optional: Add a subtle border in dark mode for better definition
        if colorScheme == .dark {
            appearance.shadowColor = UIColor(theme.shadowColor)
        }
        
        // Configure button appearance
        appearance.buttonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(theme.primaryColor)
        ]
        appearance.buttonAppearance.highlighted.titleTextAttributes = [
            .foregroundColor: UIColor(theme.primaryColor.opacity(0.7))
        ]
        
        // Configure done button appearance
        appearance.doneButtonAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(theme.primaryColor)
        ]
        appearance.doneButtonAppearance.highlighted.titleTextAttributes = [
            .foregroundColor: UIColor(theme.primaryColor.opacity(0.7))
        ]
        
        // Apply to all navigation bar instances
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        
        // For iOS 15+, also configure the toolbar appearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        }
        
        // Update the status bar style based on the theme
        updateStatusBarStyle(for: theme, colorScheme: colorScheme)
    }
    
    private func updateStatusBarStyle(for theme: Theme, colorScheme: ColorScheme) {
        // Configure status bar appearance through the navigation bar
        // The status bar style will automatically adapt based on the navigation bar's background color
        
        // For iOS 13+, we can also set the preferred status bar style in the Info.plist
        // by adding "View controller-based status bar appearance" = NO
        // and "Status bar style" = "UIStatusBarStyleDefault" or "UIStatusBarStyleLightContent"
        
        // SwiftUI will automatically choose the appropriate status bar style
        // based on the navigation bar's background color brightness
        print("Status bar style will automatically adapt to navigation bar appearance")
    }
}

// MARK: - UIFont Extension for Rounded Design
extension UIFont {
    static func rounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded) ?? systemFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }
}
