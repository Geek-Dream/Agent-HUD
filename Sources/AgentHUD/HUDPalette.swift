import AppKit

/// One semantic color token. Fixed-appearance themes still respond to changes
/// in panel opacity/contrast; classic continues to follow the system appearance.
struct HUDThemePalette {
    let accent: NSColor
    let selectionText: NSColor
    let windowTop: NSColor
    let windowMiddle: NSColor
    let windowBottom: NSColor
    let cardTop: NSColor
    let cardBottom: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let border: NSColor
    let surface: NSColor
    let surfaceRaised: NSColor

    static func palette(_ rawValue: String) -> HUDThemePalette? {
        switch rawValue {
        case "morningMist":
            return HUDThemePalette(
                accent: color(0.34, 0.40, 0.60),
                selectionText: color(0.24, 0.30, 0.49),
                windowTop: color(0.975, 0.965, 0.955),
                windowMiddle: color(0.945, 0.945, 0.94),
                windowBottom: color(0.90, 0.92, 0.93),
                cardTop: color(1, 0.995, 0.985, alpha: 0.97),
                cardBottom: color(0.96, 0.965, 0.955, alpha: 0.94),
                textPrimary: color(0.18, 0.20, 0.23),
                textSecondary: color(0.37, 0.40, 0.43),
                textTertiary: color(0.48, 0.51, 0.53),
                border: color(0.34, 0.39, 0.44, alpha: 0.14),
                surface: color(1, 0.995, 0.985, alpha: 0.96),
                surfaceRaised: color(1, 1, 1)
            )
        case "celadon":
            return HUDThemePalette(
                accent: color(0.13, 0.46, 0.39),
                selectionText: color(0.09, 0.38, 0.31),
                windowTop: color(0.94, 0.975, 0.955),
                windowMiddle: color(0.89, 0.95, 0.925),
                windowBottom: color(0.83, 0.92, 0.895),
                cardTop: color(0.98, 1, 0.99, alpha: 0.97),
                cardBottom: color(0.91, 0.97, 0.94, alpha: 0.92),
                textPrimary: color(0.09, 0.22, 0.19),
                textSecondary: color(0.28, 0.42, 0.37),
                textTertiary: color(0.39, 0.50, 0.45),
                border: color(0.12, 0.39, 0.31, alpha: 0.17),
                surface: color(0.97, 1, 0.98, alpha: 0.96),
                surfaceRaised: color(0.985, 1, 0.99)
            )
        case "starlight":
            return HUDThemePalette(
                accent: color(0.55, 0.61, 1),
                selectionText: color(0.88, 0.89, 1),
                windowTop: color(0.04, 0.045, 0.12),
                windowMiddle: color(0.075, 0.06, 0.16),
                windowBottom: color(0.025, 0.035, 0.09),
                cardTop: color(0.11, 0.12, 0.23, alpha: 0.96),
                cardBottom: color(0.065, 0.07, 0.15, alpha: 0.94),
                textPrimary: color(0.94, 0.95, 1),
                textSecondary: color(0.76, 0.78, 0.90),
                textTertiary: color(0.60, 0.64, 0.79),
                border: color(0.67, 0.65, 1, alpha: 0.22),
                surface: color(0.10, 0.10, 0.20, alpha: 0.96),
                surfaceRaised: color(0.13, 0.13, 0.25, alpha: 0.98)
            )
        case "neon":
            return HUDThemePalette(
                accent: color(0.17, 0.89, 0.94),
                selectionText: color(0.68, 0.97, 1),
                windowTop: color(0.015, 0.025, 0.065),
                windowMiddle: color(0.055, 0.015, 0.10),
                windowBottom: color(0.005, 0.02, 0.045),
                cardTop: color(0.035, 0.09, 0.14, alpha: 0.97),
                cardBottom: color(0.065, 0.025, 0.12, alpha: 0.96),
                textPrimary: color(0.90, 0.98, 1),
                textSecondary: color(0.64, 0.85, 0.92),
                textTertiary: color(0.48, 0.65, 0.76),
                border: color(0.16, 0.85, 0.94, alpha: 0.28),
                surface: color(0.035, 0.075, 0.12, alpha: 0.97),
                surfaceRaised: color(0.055, 0.10, 0.16, alpha: 0.98)
            )
        default:
            return nil
        }
    }

    private static func color(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
