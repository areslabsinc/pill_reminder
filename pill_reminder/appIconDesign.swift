import SwiftUI

// MARK: - App Icon Design View
// This view helps visualize the app icon design
// Export this at 1024x1024 for the App Store icon
struct AppIconDesign: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "7FB069").opacity(0.9), // Sage green
                    Color(hex: "B8C5D6").opacity(0.8)  // Lavender blue
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Soft white circle background for pill
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 700, height: 700)
                .blur(radius: 50)
            
            // Main pill capsule
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color.white.opacity(0.9)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 400, height: 600)
                .rotationEffect(.degrees(45))
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            
            // Pill divider line
            Rectangle()
                .fill(Color(hex: "95E1D3"))
                .frame(width: 420, height: 4)
                .rotationEffect(.degrees(45))
            
            // Heart symbol in the center
            Image(systemName: "heart.fill")
                .font(.system(size: 200, weight: .medium))
                .foregroundColor(Color(hex: "FFB5A7"))
                .shadow(color: Color(hex: "FFB5A7").opacity(0.3), radius: 10)
            
            // Clock overlay
            Image(systemName: "clock.fill")
                .font(.system(size: 80, weight: .regular))
                .foregroundColor(Color(hex: "7FB069"))
                .offset(x: 120, y: -120)
                .opacity(0.8)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 224)) // iOS app icon corner radius
    }
}

// MARK: - Launch Screen
struct LaunchScreen: View {
    @State private var isAnimating = false
    @State private var showPill = false
    @State private var showHeart = false
    @State private var showText = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "FAFAF8"),
                    Color(hex: "F5F5F3")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Animated pill and heart
                ZStack {
                    // Pill
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "7FB069"),
                                    Color(hex: "95E1D3")
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 180)
                        .rotationEffect(.degrees(isAnimating ? 0 : -90))
                        .scaleEffect(showPill ? 1.0 : 0.0)
                        .shadow(color: Color(hex: "7FB069").opacity(0.3), radius: 20)
                    
                    // Heart
                    Image(systemName: "heart.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundColor(Color(hex: "FFB5A7"))
                        .scaleEffect(showHeart ? 1.0 : 0.0)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                }
                
                // App name
                VStack(spacing: 8) {
                    Text("Pill Reminder")
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "2C3E50"))
                    
                    Text("Your Health Companion")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "6C7A89"))
                }
                .opacity(showText ? 1.0 : 0.0)
                .offset(y: showText ? 0 : 20)
            }
        }
        .onAppear {
            animateElements()
        }
    }
    
    private func animateElements() {
        // Show pill
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showPill = true
        }
        
        // Show heart
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
            showHeart = true
        }
        
        // Start pulsing
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.5)) {
            isAnimating = true
        }
        
        // Show text
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) {
            showText = true
        }
    }
}

// MARK: - Preview
struct AppIconDesign_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // App Icon Preview
            AppIconDesign()
                .previewLayout(.fixed(width: 1024, height: 1024))
                .previewDisplayName("App Icon (1024x1024)")
            
            // Launch Screen Preview
            LaunchScreen()
                .previewDevice("iPhone 14 Pro")
                .previewDisplayName("Launch Screen")
        }
    }
}

// MARK: - Icon Export Helper
// Instructions for exporting the icon:
/*
 1. Run this view in SwiftUI Preview
 2. Right-click on the preview and select "Export Preview"
 3. Save as 1024x1024 PNG
 4. Use an app icon generator tool to create all required sizes
 5. Add to Assets.xcassets
 
 Required sizes for iOS:
 - 20pt (40x40, 60x60)
 - 29pt (58x58, 87x87)
 - 40pt (80x80, 120x120)
 - 60pt (120x120, 180x180)
 - 1024x1024 (App Store)
 */
