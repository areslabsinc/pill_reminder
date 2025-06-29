import SwiftUI

// MARK: - Animation Extensions
extension Animation {
    static let soothing = Animation.easeInOut(duration: 0.3)
    static let soothingSlow = Animation.easeInOut(duration: 0.5)
    static let soothingSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let soothingBounce = Animation.spring(response: 0.5, dampingFraction: 0.6)
}

// MARK: - Pill Taking Animation View
struct PillTakingAnimation: View {
    @State private var isPillTaken = false
    @State private var pillScale: CGFloat = 1.0
    @State private var pillOpacity: Double = 1.0
    @State private var checkmarkScale: CGFloat = 0.0
    @State private var checkmarkOpacity: Double = 0.0
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Pill
            Image(systemName: "capsule.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "7FB069"))
                .scaleEffect(pillScale)
                .opacity(pillOpacity)
            
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "95E1D3"))
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
        }
        .onAppear {
            animatePillTaking()
        }
    }
    
    private func animatePillTaking() {
        // Pill shrinks and fades
        withAnimation(.easeIn(duration: 0.3)) {
            pillScale = 0.5
            pillOpacity = 0
        }
        
        // Checkmark appears with bounce
        withAnimation(.soothingBounce.delay(0.2)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        
        // Call completion after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onComplete()
        }
    }
}

// MARK: - Stock Count Animation
struct AnimatedStockCount: View {
    let from: Int
    let to: Int
    @State private var currentValue: Int
    
    init(from: Int, to: Int) {
        self.from = from
        self.to = to
        self._currentValue = State(initialValue: from)
    }
    
    var body: some View {
        Text("\(currentValue)")
            .contentTransition(.numericText())
            .onAppear {
                animateValue()
            }
    }
    
    private func animateValue() {
        let duration = 0.5
        let steps = abs(to - from)
        let stepDuration = duration / Double(steps)
        
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) {
                withAnimation(.easeOut(duration: stepDuration)) {
                    if to > from {
                        currentValue = from + i + 1
                    } else {
                        currentValue = from - i - 1
                    }
                }
            }
        }
    }
}

// MARK: - Pulsing View Modifier
struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0 : 0.7)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Gentle Shake Modifier
struct GentleShakeModifier: ViewModifier {
    @State private var shakeOffset: CGFloat = 0
    let trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, _ in
                shake()
            }
    }
    
    private func shake() {
        withAnimation(.default) {
            shakeOffset = -5
        }
        
        withAnimation(.default.delay(0.1)) {
            shakeOffset = 5
        }
        
        withAnimation(.default.delay(0.2)) {
            shakeOffset = -5
        }
        
        withAnimation(.default.delay(0.3)) {
            shakeOffset = 0
        }
    }
}

// MARK: - Slide and Fade Transition
struct SlideAndFadeModifier: ViewModifier {
    let isVisible: Bool
    let edge: Edge
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(offset)
            .animation(.soothing, value: isVisible)
    }
    
    private var offset: CGSize {
        guard !isVisible else { return .zero }
        
        switch edge {
        case .top:
            return CGSize(width: 0, height: -20)
        case .bottom:
            return CGSize(width: 0, height: 20)
        case .leading:
            return CGSize(width: -20, height: 0)
        case .trailing:
            return CGSize(width: 20, height: 0)
        }
    }
}

// MARK: - Floating Action Button
struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    @Environment(\.theme) var theme
    
    var body: some View {
        Button(action: {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    theme.primaryColor,
                                    theme.primaryColor.opacity(0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: theme.primaryColor.opacity(0.3), radius: isPressed ? 4 : 8, y: isPressed ? 2 : 4)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .animation(.soothingSpring, value: isPressed)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    @Environment(\.theme) var theme
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundColor(theme.secondaryColor)
                .rotationEffect(.degrees(isAnimating ? 10 : -10))
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack(spacing: Spacing.small) {
                Text(title)
                    .font(.soothing(.title2))
                    .foregroundColor(theme.textColor)
                
                Text(subtitle)
                    .font(.soothing(.body))
                    .foregroundColor(theme.secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.large)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.soothing(.headline))
                }
                .themedButton()
                .padding(.top, Spacing.medium)
            }
        }
        .padding(Spacing.extraLarge)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Success Celebration View
struct SuccessCelebration: View {
    @State private var isAnimating = false
    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        ZStack {
            ForEach(confettiPieces) { piece in
                Circle()
                    .fill(piece.color)
                    .frame(width: 10, height: 10)
                    .position(piece.position)
                    .opacity(piece.opacity)
            }
        }
        .onAppear {
            createConfetti()
            animateConfetti()
        }
    }
    
    private func createConfetti() {
        let colors = [
            Color(hex: "95E1D3"),
            Color(hex: "FFB5A7"),
            Color(hex: "B8C5D6"),
            Color(hex: "7FB069")
        ]
        
        for _ in 0..<20 {
            confettiPieces.append(ConfettiPiece(
                color: colors.randomElement()!,
                position: CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2),
                opacity: 1.0
            ))
        }
    }
    
    private func animateConfetti() {
        for i in confettiPieces.indices {
            let randomX = CGFloat.random(in: -100...100)
            let randomY = CGFloat.random(in: -200...(-50))
            
            withAnimation(.easeOut(duration: 1.5).delay(Double(i) * 0.05)) {
                confettiPieces[i].position.x += randomX
                confettiPieces[i].position.y += randomY
                confettiPieces[i].opacity = 0
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    var position: CGPoint
    var opacity: Double
}

// MARK: - View Extensions for Animations
extension View {
    func pulsingEffect(color: Color = Color(hex: "7FB069")) -> some View {
        modifier(PulsingModifier(color: color))
    }
    
    func gentleShake(trigger: Bool) -> some View {
        modifier(GentleShakeModifier(trigger: trigger))
    }
    
    func slideAndFade(isVisible: Bool, edge: Edge = .bottom) -> some View {
        modifier(SlideAndFadeModifier(isVisible: isVisible, edge: edge))
    }
    
    func soothingTransition() -> some View {
        self.transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 1.2).combined(with: .opacity)
        ))
    }
}

// MARK: - Loading Indicator
struct SoothingLoadingIndicator: View {
    @State private var isAnimating = false
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: Spacing.small) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(theme.primaryColor)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
