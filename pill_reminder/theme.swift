import SwiftUI

// MARK: - Enhanced Theme Protocol
protocol Theme {
    var name: String { get }
    var primaryColor: Color { get }
    var secondaryColor: Color { get }
    var accentColor: Color { get }
    var backgroundColor: Color { get }
    var secondaryBackgroundColor: Color { get }
    var tertiaryBackgroundColor: Color { get }
    var textColor: Color { get }
    var secondaryTextColor: Color { get }
    var successColor: Color { get }
    var warningColor: Color { get }
    var errorColor: Color { get }
    var shadowColor: Color { get }
}

// MARK: - Smart Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    // MARK: - Smart Color Adaptation
    /// Creates a color that adapts intelligently to light/dark mode
    static func Adaptive(light: String, dark: String) -> Color {
        return Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(Color(hex: dark))
            default:
                return UIColor(Color(hex: light))
            }
        })
    }
    
    /// Creates a color that automatically adjusts brightness for dark mode
    static func smartAdaptive(hex: String, darknessFactor: Double = 0.3, brightnessFactor: Double = 0.2) -> Color {
        Color(UIColor { traitCollection in
            let baseColor = Color(hex: hex)
            
            switch traitCollection.userInterfaceStyle {
            case .dark:
                // Make colors darker and more muted for dark mode
                return UIColor(baseColor.adjustedForDarkMode(darknessFactor: darknessFactor))
            default:
                // Keep original colors for light mode, or slightly brighten if needed
                return UIColor(baseColor.adjustedForLightMode(brightnessFactor: brightnessFactor))
            }
        })
    }
    
    /// Adjusts color for dark mode by reducing saturation and brightness
    private func adjustedForDarkMode(darknessFactor: Double = 0.3) -> Color {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Reduce saturation and brightness for dark mode
        let newSaturation = saturation * (1 - CGFloat(darknessFactor * 0.5))
        let newBrightness = brightness * (1 - CGFloat(darknessFactor))
        
        return Color(UIColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: alpha))
    }
    
    /// Slightly adjusts color for light mode if needed
    private func adjustedForLightMode(brightnessFactor: Double = 0.2) -> Color {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // Slightly increase brightness for light mode if the color is too dark
        let newBrightness = min(1.0, brightness + CGFloat(brightnessFactor * (1 - brightness)))
        
        return Color(UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha))
    }
    
    /// Creates adaptive background colors that work well in both modes
    static func adaptiveBackground(light: String, darkAdjustment: Double = 0.9) -> Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                // For dark mode, use a much darker version of the light color
                let baseColor = Color(hex: light)
                let uiColor = UIColor(baseColor)
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                
                uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                
                // Create a very dark version with reduced saturation
                let darkBrightness = brightness * CGFloat(1 - darkAdjustment)
                let darkSaturation = saturation * 0.3
                
                return UIColor(hue: hue, saturation: darkSaturation, brightness: darkBrightness, alpha: alpha)
            default:
                return UIColor(Color(hex: light))
            }
        })
    }
    
    /// Creates adaptive text colors
    static func adaptiveText(light: String, dark: String? = nil) -> Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                if let dark = dark {
                    return UIColor(Color(hex: dark))
                } else {
                    // Auto-generate light version of the color
                    let baseColor = Color(hex: light)
                    let uiColor = UIColor(baseColor)
                    var hue: CGFloat = 0
                    var saturation: CGFloat = 0
                    var brightness: CGFloat = 0
                    var alpha: CGFloat = 0
                    
                    uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                    
                    // Create a lighter version for dark mode
                    let lightBrightness = min(1.0, brightness + (1 - brightness) * 0.7)
                    let lightSaturation = saturation * 0.8
                    
                    return UIColor(hue: hue, saturation: lightSaturation, brightness: lightBrightness, alpha: alpha)
                }
            default:
                return UIColor(Color(hex: light))
            }
        })
    }
}

// MARK: - Enhanced Soothing Theme
struct SoothingTheme: Theme {
    let name = "Soothing"
    
    // Primary colors with smart adaptation
    let primaryColor = Color.smartAdaptive(hex: "7FB069", darknessFactor: 0.2) // Soft sage green
    let secondaryColor = Color.smartAdaptive(hex: "B8C5D6", darknessFactor: 0.3) // Lavender blue
    let accentColor = Color.smartAdaptive(hex: "FFB5A7", darknessFactor: 0.2) // Warm peach
    
    // Background colors with special dark mode handling
    let backgroundColor = Color.adaptiveBackground(light: "FAFAF8", darkAdjustment: 0.95) // Off-white
    let secondaryBackgroundColor = Color.adaptiveBackground(light: "F5F5F3", darkAdjustment: 0.85) // Light gray
    let tertiaryBackgroundColor = Color.adaptiveBackground(light: "EFEFED", darkAdjustment: 0.8) // Lighter gray
    
    // Text colors with automatic light/dark adaptation
    let textColor = Color.adaptiveText(light: "2C3E50", dark: "E8E8E8") // Soft charcoal to light gray
    let secondaryTextColor = Color.adaptiveText(light: "6C7A89", dark: "B0B0B0") // Muted gray to lighter gray
    
    // Status colors with smart adaptation
    let successColor = Color.smartAdaptive(hex: "95E1D3", darknessFactor: 0.25) // Mint green
    let warningColor = Color.smartAdaptive(hex: "F3B63A", darknessFactor: 0.2) // Soft amber
    let errorColor = Color.smartAdaptive(hex: "E08B7B", darknessFactor: 0.15) // Muted coral
    
    // Shadow with adaptive opacity
    var shadowColor: Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor.black.withAlphaComponent(0.3)
            default:
                return UIColor.black.withAlphaComponent(0.05)
            }
        })
    }
}

// MARK: - Enhanced Ocean Theme
struct OceanTheme: Theme {
    let name = "Ocean"
    
    let primaryColor = Color.smartAdaptive(hex: "5B9DC1", darknessFactor: 0.2) // Ocean blue
    let secondaryColor = Color.smartAdaptive(hex: "89CFF0", darknessFactor: 0.3) // Sky blue
    let accentColor = Color.smartAdaptive(hex: "F4E4C1", darknessFactor: 0.4) // Sand
    
    let backgroundColor = Color.adaptiveBackground(light: "F8FBFF", darkAdjustment: 0.95) // Light blue white
    let secondaryBackgroundColor = Color.adaptiveBackground(light: "EFF5FB", darkAdjustment: 0.85)
    let tertiaryBackgroundColor = Color.adaptiveBackground(light: "E6EFF8", darkAdjustment: 0.8)
    
    let textColor = Color.adaptiveText(light: "1E3A5F", dark: "E0F0FF") // Deep ocean to light blue
    let secondaryTextColor = Color.adaptiveText(light: "5C7A99", dark: "A0C0D0")
    
    let successColor = Color.smartAdaptive(hex: "7FC8A9", darknessFactor: 0.25) // Sea green
    let warningColor = Color.smartAdaptive(hex: "FFD93D", darknessFactor: 0.2) // Sunny yellow
    let errorColor = Color.smartAdaptive(hex: "FF8B94", darknessFactor: 0.15) // Coral
    
    var shadowColor: Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor.blue.withAlphaComponent(0.2)
            default:
                return UIColor.blue.withAlphaComponent(0.05)
            }
        })
    }
}

// MARK: - Enhanced Lavender Theme
struct LavenderTheme: Theme {
    let name = "Lavender"
    
    let primaryColor = Color.smartAdaptive(hex: "B19CD9", darknessFactor: 0.2) // Soft purple
    let secondaryColor = Color.smartAdaptive(hex: "DCC9E8", darknessFactor: 0.3) // Light lavender
    let accentColor = Color.smartAdaptive(hex: "FFC8DD", darknessFactor: 0.2) // Pink
    
    let backgroundColor = Color.adaptiveBackground(light: "FAF9FC", darkAdjustment: 0.95) // Lavender white
    let secondaryBackgroundColor = Color.adaptiveBackground(light: "F5F3F8", darkAdjustment: 0.85)
    let tertiaryBackgroundColor = Color.adaptiveBackground(light: "EFEDF3", darkAdjustment: 0.8)
    
    let textColor = Color.adaptiveText(light: "4A3C5C", dark: "E8E0F0") // Deep purple to light purple
    let secondaryTextColor = Color.adaptiveText(light: "7B6D8D", dark: "C0B0D0")
    
    let successColor = Color.smartAdaptive(hex: "C7E9B0", darknessFactor: 0.25) // Soft green
    let warningColor = Color.smartAdaptive(hex: "FFDCA9", darknessFactor: 0.2) // Peach
    let errorColor = Color.smartAdaptive(hex: "FFB3BA", darknessFactor: 0.15) // Rose
    
    var shadowColor: Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor.purple.withAlphaComponent(0.2)
            default:
                return UIColor.purple.withAlphaComponent(0.05)
            }
        })
    }
}

// MARK: - Theme Manager (Updated)
class ThemeManager: ObservableObject {
    @Published var currentTheme: Theme = SoothingTheme()
    
    static let shared = ThemeManager()
    
    let availableThemes: [Theme] = [
        SoothingTheme(),
        OceanTheme(),
        LavenderTheme()
    ]
    
    private init() {
        // Load saved theme preference
        if let savedThemeName = UserDefaults.standard.string(forKey: "selectedTheme") {
            if let theme = availableThemes.first(where: { $0.name == savedThemeName }) {
                currentTheme = theme
            }
        }
        
        // Listen for appearance changes to update UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: Notification.Name("UIUserInterfaceStyleDidChange"),
            object: nil
        )
    }
    
    @objc private func appearanceChanged() {
        // Force UI update when appearance changes
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func setTheme(_ theme: Theme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.name, forKey: "selectedTheme")
    }
}

// MARK: - Enhanced Theme Environment Key
struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = SoothingTheme()
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Rest of the theme system remains the same
struct ThemedBackground: ViewModifier {
    @Environment(\.theme) var theme
    var style: BackgroundStyle = .primary
    
    enum BackgroundStyle {
        case primary, secondary, tertiary
    }
    
    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary:
            return theme.backgroundColor
        case .secondary:
            return theme.secondaryBackgroundColor
        case .tertiary:
            return theme.tertiaryBackgroundColor
        }
    }
}

struct ThemedCard: ViewModifier {
    @Environment(\.theme) var theme
    var padding: CGFloat = 16
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.backgroundColor)
                    .shadow(color: theme.shadowColor, radius: 8, x: 0, y: 4)
            )
    }
}

struct ThemedButton: ViewModifier {
    @Environment(\.theme) var theme
    var style: ButtonStyle = .primary
    var isDisabled: Bool = false
    
    enum ButtonStyle {
        case primary, secondary, ghost
    }
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .opacity(isDisabled ? 0.6 : 1.0)
    }
    
    private var backgroundColor: Color {
        if isDisabled {
            return theme.secondaryBackgroundColor
        }
        
        switch style {
        case .primary:
            return theme.primaryColor
        case .secondary:
            return theme.secondaryColor
        case .ghost:
            return Color.clear
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return theme.textColor
        case .ghost:
            return theme.primaryColor
        }
    }
}

// MARK: - View Extensions
extension View {
    func themedBackground(style: ThemedBackground.BackgroundStyle = .primary) -> some View {
        modifier(ThemedBackground(style: style))
    }
    
    func themedCard(padding: CGFloat = 16) -> some View {
        modifier(ThemedCard(padding: padding))
    }
    
    func themedButton(style: ThemedButton.ButtonStyle = .primary, isDisabled: Bool = false) -> some View {
        modifier(ThemedButton(style: style, isDisabled: isDisabled))
    }
    
    func soothingGradient() -> some View {
        self.background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.adaptiveBackground(light: "FAFAF8"),
                    Color.adaptiveBackground(light: "F5F5F3")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Typography (Enhanced)
extension Font {
    static func soothing(_ style: SoothingTextStyle) -> Font {
        switch style {
        case .largeTitle:
            return .system(size: 34, weight: .medium, design: .rounded)
        case .title:
            return .system(size: 28, weight: .medium, design: .rounded)
        case .title2:
            return .system(size: 22, weight: .medium, design: .rounded)
        case .title3:
            return .system(size: 20, weight: .regular, design: .rounded)
        case .headline:
            return .system(size: 17, weight: .medium, design: .rounded)
        case .body:
            return .system(size: 17, weight: .regular, design: .rounded)
        case .callout:
            return .system(size: 16, weight: .regular, design: .rounded)
        case .subheadline:
            return .system(size: 15, weight: .regular, design: .rounded)
        case .footnote:
            return .system(size: 13, weight: .regular, design: .rounded)
        case .caption:
            return .system(size: 12, weight: .regular, design: .rounded)
        case .caption2:
            return .system(size: 11, weight: .regular, design: .rounded)
        }
    }
}

enum SoothingTextStyle {
    case largeTitle, title, title2, title3
    case headline, body, callout, subheadline
    case footnote, caption, caption2
}

// MARK: - Common Spacing
struct Spacing {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
    static let huge: CGFloat = 48
}

// MARK: - Corner Radius
struct CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    static let round: CGFloat = 999
}
