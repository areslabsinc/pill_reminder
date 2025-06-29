import SwiftUI
import CoreData

// MARK: - Height Preference Key
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Swipe Action Model
struct SwipeAction {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
}

// MARK: - Swipeable Card View
struct SwipeableCard<Content: View>: View {
    @ViewBuilder let content: Content
    let leadingActions: [SwipeAction]
    let trailingActions: [SwipeAction]
    var isSwipeEnabled: Bool = true
    
    @State private var offset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    @State private var actionTriggered = false
    @GestureState private var isDragging = false
    @State private var hapticTriggered = false
    @State private var currentGestureId = UUID()
    @State private var shouldKeepTrailingActionsOpen = false
    @State private var initialDragDirection: DragDirection? = nil
    @State private var contentHeight: CGFloat = 0
    
    @Environment(\.theme) var theme
    
    // Swipe thresholds
    private let actionThreshold: CGFloat = 80
    private let fullSwipeThreshold: CGFloat = 200
    private let minimumSwipeDistance: CGFloat = 10
    private let verticalSwipeThreshold: CGFloat = 50
    
    private enum DragDirection {
        case horizontal
        case vertical
        case undetermined
    }
    
    var body: some View {
        ZStack {
            // Background actions
            HStack(spacing: 0) {
                // Leading actions (right swipe)
                if offset > 0 && !leadingActions.isEmpty {
                    leadingActionView
                        .frame(width: offset)
                        .frame(height: contentHeight)
                }
                
                Spacer()
                
                // Trailing actions (left swipe)
                if offset < 0 && !trailingActions.isEmpty {
                    trailingActionView
                        .frame(width: abs(offset))
                        .frame(height: contentHeight)
                }
            }
            
            // Main content with tap gesture for closing actions
            content
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
                    }
                )
                .onPreferenceChange(HeightPreferenceKey.self) { height in
                    contentHeight = height
                }
                .offset(x: offset)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if shouldKeepTrailingActionsOpen && offset != 0 {
                                withAnimation(.soothingSpring) {
                                    offset = 0
                                    shouldKeepTrailingActionsOpen = false
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    isSwipeEnabled ? createDragGesture() : nil
                )
                .animation(.soothingSpring, value: offset)
        }
        .onChange(of: isDragging) { _, isDragging in
            if !isDragging && !actionTriggered && !shouldKeepTrailingActionsOpen {
                // Spring back if not dragging and no action triggered
                withAnimation(.soothingSpring) {
                    offset = 0
                }
                hapticTriggered = false
            }
        }
    }
    
    // Create drag gesture with proper handling
    private func createDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                onDragChanged(value: value, width: UIScreen.main.bounds.width)
            }
            .onEnded { value in
                onDragEnded(value: value, width: UIScreen.main.bounds.width)
            }
    }
    
    // MARK: - Leading Action View (Right Swipe)
    private var leadingActionView: some View {
        HStack(spacing: 0) {
            if let firstAction = leadingActions.first {
                // Full swipe action
                HStack {
                    Image(systemName: firstAction.icon)
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    if offset > actionThreshold {
                        Text(firstAction.title)
                            .font(.soothing(.callout))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .background(firstAction.color)
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerAction(firstAction)
                }
            }
        }
    }
    
    // MARK: - Trailing Action View (Left Swipe)
    private var trailingActionView: some View {
        HStack(spacing: 0) {
            ForEach(trailingActions.indices, id: \.self) { index in
                let action = trailingActions[index]
                let width = abs(offset) / CGFloat(trailingActions.count)
                
                Button(action: {
                    triggerAction(action)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.title3)
                            .foregroundColor(.white)
                        
                        if abs(offset) > actionThreshold * 1.5 {
                            Text(action.title)
                                .font(.soothing(.caption2))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                }
                .background(action.color)
                .contentShape(Rectangle())
            }
        }
    }
    
    // MARK: - Gesture Handlers
    private func onDragChanged(value: DragGesture.Value, width: CGFloat) {
        let horizontalAmount = abs(value.translation.width)
        let verticalAmount = abs(value.translation.height)
        
        // Determine drag direction on first significant movement
        if initialDragDirection == nil {
            if verticalAmount > 10 || horizontalAmount > 10 {
                // Use a lower threshold for vertical detection to prioritize scrolling
                if verticalAmount > horizontalAmount * 1.5 {
                    // Clearly vertical - prioritize scroll
                    initialDragDirection = .vertical
                    return
                } else if horizontalAmount > verticalAmount * 1.5 {
                    // Clearly horizontal
                    initialDragDirection = .horizontal
                } else {
                    // For ambiguous gestures, prefer vertical scrolling
                    initialDragDirection = .vertical
                    return
                }
            }
        }
        
        // If we've determined it's a vertical scroll, ignore horizontal movement
        if initialDragDirection == .vertical {
            return
        }
        
        // Add throttling
        if abs(value.translation.width - previousOffset) < 2 {
            return
        }
        
        // Only process horizontal swipes
        if initialDragDirection == .horizontal {
            let translation = value.translation.width
            
            // Add resistance at edges
            if translation > 0 && leadingActions.isEmpty { return }
            if translation < 0 && trailingActions.isEmpty { return }
            
            // Close trailing actions if swiping right
            if translation > 10 && shouldKeepTrailingActionsOpen {
                shouldKeepTrailingActionsOpen = false
            }
            
            // Apply resistance formula
            let resistance: CGFloat = 0.7
            if abs(translation) > actionThreshold {
                let excess = abs(translation) - actionThreshold
                let resistedExcess = excess * resistance
                offset = translation > 0
                    ? actionThreshold + resistedExcess
                    : -(actionThreshold + resistedExcess)
            } else {
                offset = translation
            }
            
            // Haptic feedback at threshold
            if abs(offset) >= actionThreshold && !hapticTriggered {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hapticTriggered = true
            }
            
            previousOffset = offset
        }
    }
    
    private func onDragEnded(value: DragGesture.Value, width: CGFloat) {
        let translation = value.translation.width
        let velocity = value.predictedEndTranslation.width
        
        // Reset direction tracking
        defer { initialDragDirection = nil }
        
        // If it was a vertical gesture or no horizontal movement, just reset
        if initialDragDirection == .vertical || abs(translation) < 10 {
            withAnimation(.soothingSpring) {
                offset = 0
            }
            hapticTriggered = false
            return
        }
        
        // Check for full swipe
        if translation > fullSwipeThreshold || velocity > 800 {
            if let action = leadingActions.first {
                triggerFullSwipe(action: action, direction: .leading)
                return
            }
        }
        
        // Check for action trigger threshold
        if abs(translation) > actionThreshold {
            if translation > 0, let action = leadingActions.first {
                // Trigger action immediately for leading swipe
                triggerAction(action)
            } else if translation < 0 && !trailingActions.isEmpty {
                // Show trailing actions
                withAnimation(.soothingSpring) {
                    offset = -actionThreshold * 1.5
                    shouldKeepTrailingActionsOpen = true
                }
            }
        } else {
            // Spring back
            withAnimation(.soothingSpring) {
                offset = 0
            }
            hapticTriggered = false
            shouldKeepTrailingActionsOpen = false
        }
    }
    
    // MARK: - Action Handlers
    private func triggerAction(_ action: SwipeAction) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Reset position first
        withAnimation(.soothingSpring) {
            offset = 0
            shouldKeepTrailingActionsOpen = false
        }
        
        // Execute action after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action.action()
        }
        
        hapticTriggered = false
    }
    
    private func triggerFullSwipe(action: SwipeAction, direction: Edge) {
        actionTriggered = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Animate off screen
        withAnimation(.easeOut(duration: 0.3)) {
            offset = direction == .leading ? 500 : -500
        }
        
        // Execute action
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action.action()
            
            // Reset after action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                offset = 0
                actionTriggered = false
                hapticTriggered = false
                shouldKeepTrailingActionsOpen = false
            }
        }
    }
}

// MARK: - Global Tap Gesture Modifier
struct GlobalTapGesture: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: action)
            )
    }
}

extension View {
    func onGlobalTap(perform action: @escaping () -> Void) -> some View {
        self.modifier(GlobalTapGesture(action: action))
    }
}

// MARK: - Swipe Hint Overlay
struct SwipeHintOverlay: View {
    @State private var hintOffset: CGFloat = 0
    @State private var showHint = false
    @State private var showLongPressHint = false
    let direction: SwipeDirection
    
    @Environment(\.theme) var theme
    @AppStorage("hasSeenSwipeHint") private var hasSeenSwipeHint = false
    @AppStorage("hasSeenLongPressHint") private var hasSeenLongPressHint = false
    
    enum SwipeDirection {
        case leading, trailing
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if showHint {
                HStack {
                    if direction == .trailing {
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        if direction == .leading {
                            Image(systemName: "chevron.right")
                        }
                        
                        Text(direction == .leading ? "Swipe to take" : "Swipe for options")
                            .font(.soothing(.caption))
                        
                        if direction == .trailing {
                            Image(systemName: "chevron.left")
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .offset(x: hintOffset)
                    
                    if direction == .leading {
                        Spacer()
                    }
                }
                .transition(.opacity)
            }
            
            if showLongPressHint {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                        Text("Long press for more options")
                            .font(.soothing(.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            // Show hints only once per install
            if !hasSeenSwipeHint {
                showHintAnimation()
            }
        }
    }
    
    private func showHintAnimation() {
        withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
            showHint = true
        }
        
        withAnimation(.easeInOut(duration: 1.0).delay(1.5).repeatCount(2, autoreverses: true)) {
            hintOffset = direction == .leading ? 20 : -20
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(5.0)) {
            showHint = false
            hasSeenSwipeHint = true
        }
        
        // Show long press hint after swipe hint
        if !hasSeenLongPressHint {
            withAnimation(.easeOut(duration: 0.5).delay(6.0)) {
                showLongPressHint = true
            }
            
            withAnimation(.easeOut(duration: 0.5).delay(10.0)) {
                showLongPressHint = false
                hasSeenLongPressHint = true
            }
        }
    }
}

// MARK: - Snooze Options Sheet
struct SnoozeOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme
    let medication: Medication
    let onSnooze: (Int) -> Void
    
    let snoozeOptions = [
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (120, "2 hours")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                theme.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.warningColor.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(theme.warningColor)
                        }
                        
                        Text("Snooze Reminder")
                            .font(.soothing(.title2))
                            .foregroundColor(theme.textColor)
                        
                        Text(medication.name ?? "Medication")
                            .font(.soothing(.subheadline))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    .padding(.top, Spacing.large)
                    .padding(.bottom, Spacing.medium)
                    
                    // Snooze options
                    VStack(spacing: Spacing.small) {
                        ForEach(snoozeOptions, id: \.0) { minutes, label in
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSnooze(minutes)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(theme.warningColor)
                                        .frame(width: 30)
                                    
                                    Text(label)
                                        .font(.soothing(.body))
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(theme.secondaryTextColor)
                                }
                                .foregroundColor(theme.textColor)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                                        .fill(theme.secondaryBackgroundColor)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(theme.primaryColor)
                }
            }
        }
    }
}
