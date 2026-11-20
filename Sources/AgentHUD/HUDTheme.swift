import AppKit
import SwiftUI

enum HUDTheme {
    static let accent = adaptiveColor(
        light: rgb(0.19, 0.32, 0.76),
        dark: rgb(0.47, 0.60, 1.00)
    )
    static let selectionText = adaptiveColor(
        light: rgb(0.16, 0.29, 0.70),
        dark: rgb(0.80, 0.86, 1.00)
    )
    static let windowTint = adaptiveColor(
        light: rgb(0.92, 0.94, 1.00, alpha: 0.90),
        dark: rgb(0.025, 0.035, 0.085, alpha: 0.96)
    )
    static let windowGradient = adaptiveColors(
        light: [
            rgb(0.95, 0.965, 1.00),
            rgb(0.88, 0.91, 0.99),
            rgb(0.82, 0.87, 0.99)
        ],
        dark: [
            rgb(0.015, 0.020, 0.060),
            rgb(0.020, 0.028, 0.072),
            rgb(0.008, 0.013, 0.038)
        ]
    )
    static let cardGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.95),
            rgb(0.965, 0.975, 1.00, alpha: 0.88)
        ],
        dark: [
            rgb(0.075, 0.095, 0.165, alpha: 0.94),
            rgb(0.045, 0.060, 0.120, alpha: 0.91)
        ]
    )
    static let cardBorderGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.92),
            rgb(0.43, 0.52, 0.75, alpha: 0.14)
        ],
        dark: [
            rgb(0.48, 0.58, 0.88, alpha: 0.25),
            rgb(0.25, 0.34, 0.62, alpha: 0.10)
        ]
    )
    static let filterBarGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.52),
            rgb(0.93, 0.95, 1.00, alpha: 0.36)
        ],
        dark: [
            rgb(0.070, 0.085, 0.170, alpha: 0.94),
            rgb(0.035, 0.050, 0.120, alpha: 0.94)
        ]
    )
    static let filterPillGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.66),
            rgb(0.94, 0.96, 1.00, alpha: 0.48)
        ],
        dark: [
            rgb(0.12, 0.15, 0.25, alpha: 0.52),
            rgb(0.075, 0.095, 0.18, alpha: 0.42)
        ]
    )
    static let selectionGradient = adaptiveColors(
        light: [
            rgb(0.68, 0.77, 1.00, alpha: 0.94),
            rgb(0.86, 0.90, 1.00, alpha: 0.88)
        ],
        dark: [
            rgb(0.17, 0.27, 0.62, alpha: 0.98),
            rgb(0.075, 0.11, 0.30, alpha: 0.98)
        ]
    )
    static let brandGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.96),
            rgb(0.93, 0.95, 1.00, alpha: 0.86)
        ],
        dark: [
            rgb(0.10, 0.15, 0.30, alpha: 0.98),
            rgb(0.055, 0.080, 0.19, alpha: 0.98)
        ]
    )
    static let footerGradient = adaptiveColors(
        light: [
            rgb(0.96, 0.97, 1.00, alpha: 0.62),
            rgb(0.90, 0.93, 1.00, alpha: 0.82)
        ],
        dark: [
            rgb(0.040, 0.055, 0.120, alpha: 0.94),
            rgb(0.025, 0.035, 0.085, alpha: 0.98)
        ]
    )
    static let glassSheen = adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.70),
        dark: rgb(0.30, 0.36, 0.78, alpha: 0.055)
    )
    static let auroraSheen = adaptiveColor(
        light: rgb(0.48, 0.64, 1.00, alpha: 0.22),
        dark: rgb(0.25, 0.16, 0.70, alpha: 0.065)
    )
    static let surface = adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.94),
        dark: rgb(0.070, 0.085, 0.125, alpha: 0.96)
    )
    static let surfaceRaised = adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.99),
        dark: rgb(0.095, 0.115, 0.165, alpha: 0.98)
    )
    static let controlFill = adaptiveColor(
        light: NSColor(calibratedWhite: 0.08, alpha: 0.040),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.060)
    )
    static let toolbarIdle = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.00),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.035)
    )
    static let controlHover = adaptiveColor(
        light: NSColor(calibratedWhite: 0.05, alpha: 0.09),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    )
    static let border = adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.09),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    )
    static let borderStrong = adaptiveColor(
        light: NSColor(calibratedWhite: 0.025, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.20)
    )
    static let divider = adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.09)
    )
    static let textPrimary = adaptiveColor(
        light: rgb(0.075, 0.085, 0.115),
        dark: rgb(0.94, 0.95, 0.985)
    )
    static let textSecondary = adaptiveColor(
        light: rgb(0.31, 0.34, 0.40),
        dark: rgb(0.66, 0.70, 0.79)
    )
    static let textTertiary = adaptiveColor(
        light: rgb(0.48, 0.51, 0.58),
        dark: rgb(0.48, 0.53, 0.63)
    )
    static let working = adaptiveColor(
        light: rgb(0.13, 0.39, 0.88),
        dark: rgb(0.36, 0.66, 1.00)
    )
    static let waiting = adaptiveColor(
        light: rgb(0.60, 0.40, 0.06),
        dark: rgb(0.95, 0.73, 0.32)
    )
    static let completed = adaptiveColor(
        light: rgb(0.08, 0.52, 0.31),
        dark: rgb(0.32, 0.82, 0.62)
    )
    static let failed = adaptiveColor(
        light: rgb(0.78, 0.17, 0.25),
        dark: rgb(1.00, 0.43, 0.52)
    )
    static let codex = adaptiveColor(
        light: rgb(0.12, 0.43, 0.94),
        dark: rgb(0.28, 0.68, 1.00)
    )
    static let claude = adaptiveColor(
        light: rgb(0.94, 0.43, 0.08),
        dark: rgb(1.00, 0.50, 0.18)
    )
    static let pi = adaptiveColor(
        light: rgb(0.16, 0.50, 0.29),
        dark: rgb(0.48, 0.82, 0.56)
    )
    static let opencode = adaptiveColor(
        light: rgb(0.02, 0.48, 0.46),
        dark: rgb(0.31, 0.80, 0.77)
    )
    static let important = adaptiveColor(
        light: rgb(0.67, 0.43, 0.06),
        dark: rgb(0.96, 0.75, 0.30)
    )
    static let glyphCyan = adaptiveColor(
        light: rgb(0.02, 0.60, 0.92),
        dark: rgb(0.20, 0.86, 1.00)
    )
    static let glyphViolet = adaptiveColor(
        light: rgb(0.48, 0.28, 0.94),
        dark: rgb(0.68, 0.48, 1.00)
    )
    static let glyphPink = adaptiveColor(
        light: rgb(0.83, 0.24, 0.62),
        dark: rgb(1.00, 0.42, 0.76)
    )
    static let glyphOrange = adaptiveColor(
        light: rgb(0.94, 0.40, 0.08),
        dark: rgb(1.00, 0.58, 0.20)
    )
    static let glyphMint = adaptiveColor(
        light: rgb(0.08, 0.62, 0.38),
        dark: rgb(0.30, 0.92, 0.62)
    )
    static let rowShadow = adaptiveColor(
        light: rgb(0.20, 0.27, 0.48, alpha: 0.12),
        dark: rgb(0.00, 0.00, 0.00, alpha: 0.42)
    )

    enum Shadow {
        static let rowBase = (
            color: HUDTheme.rowShadow,
            radius: CGFloat(7),
            y: CGFloat(2)
        )

        static func status(color: Color, hovered: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
            (
                color: color.opacity(hovered ? 0.22 : 0.14),
                radius: CGFloat(hovered ? 8 : 6),
                y: CGFloat(hovered ? 3 : 2)
            )
        }
    }

    private static func rgb(
        _ red: Double,
        _ green: Double,
        _ blue: Double,
        alpha: Double = 1
    ) -> NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }

    private static func adaptiveColors(light: [NSColor], dark: [NSColor]) -> [Color] {
        zip(light, dark).map { lightColor, darkColor in
            adaptiveColor(light: lightColor, dark: darkColor)
        }
    }
}
