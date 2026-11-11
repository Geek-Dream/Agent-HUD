import AppKit
import SwiftUI

enum HUDTheme {
    static let windowTint = adaptiveColor(
        light: NSColor(calibratedRed: 0.955, green: 0.966, blue: 0.982, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.045, green: 0.060, blue: 0.085, alpha: 0.94)
    )
    static let surface = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.82),
        dark: NSColor(calibratedRed: 0.10, green: 0.125, blue: 0.16, alpha: 0.82)
    )
    static let surfaceRaised = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.96),
        dark: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.20, alpha: 0.96)
    )
    static let controlFill = adaptiveColor(
        light: NSColor(calibratedWhite: 0.06, alpha: 0.07),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    )
    static let controlHover = adaptiveColor(
        light: NSColor(calibratedWhite: 0.05, alpha: 0.12),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.17)
    )
    static let border = adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.21)
    )
    static let borderStrong = adaptiveColor(
        light: NSColor(calibratedWhite: 0.025, alpha: 0.28),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.34)
    )
    static let divider = adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.14),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.16)
    )
    static let textPrimary = adaptiveColor(
        light: NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.10, alpha: 1),
        dark: NSColor(calibratedRed: 0.975, green: 0.985, blue: 1.0, alpha: 1)
    )
    static let textSecondary = adaptiveColor(
        light: NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.33, alpha: 1),
        dark: NSColor(calibratedRed: 0.81, green: 0.85, blue: 0.91, alpha: 1)
    )
    static let textTertiary = adaptiveColor(
        light: NSColor(calibratedRed: 0.36, green: 0.40, blue: 0.47, alpha: 1),
        dark: NSColor(calibratedRed: 0.65, green: 0.70, blue: 0.78, alpha: 1)
    )
    static let working = adaptiveColor(
        light: NSColor(calibratedRed: 0.0, green: 0.30, blue: 0.76, alpha: 1),
        dark: NSColor(calibratedRed: 0.33, green: 0.68, blue: 1.0, alpha: 1)
    )
    static let waiting = adaptiveColor(
        light: NSColor(calibratedRed: 0.58, green: 0.35, blue: 0.0, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.20, alpha: 1)
    )
    static let completed = adaptiveColor(
        light: NSColor(calibratedRed: 0.0, green: 0.44, blue: 0.24, alpha: 1),
        dark: NSColor(calibratedRed: 0.27, green: 0.90, blue: 0.58, alpha: 1)
    )
    static let failed = adaptiveColor(
        light: NSColor(calibratedRed: 0.72, green: 0.05, blue: 0.14, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.46, alpha: 1)
    )
    static let codex = adaptiveColor(
        light: NSColor(calibratedRed: 0.0, green: 0.30, blue: 0.76, alpha: 1),
        dark: NSColor(calibratedRed: 0.33, green: 0.68, blue: 1.0, alpha: 1)
    )
    static let claude = adaptiveColor(
        light: NSColor(calibratedRed: 0.66, green: 0.20, blue: 0.03, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.28, alpha: 1)
    )
    static let pi = adaptiveColor(
        light: NSColor(calibratedRed: 0.09, green: 0.42, blue: 0.06, alpha: 1),
        dark: NSColor(calibratedRed: 0.48, green: 0.89, blue: 0.36, alpha: 1)
    )
    static let important = adaptiveColor(
        light: NSColor(calibratedRed: 0.66, green: 0.37, blue: 0.0, alpha: 1),
        dark: NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.20, alpha: 1)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }
}
