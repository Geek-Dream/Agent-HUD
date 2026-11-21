import AppKit
import SwiftUI

enum HUDTheme {
    static func themed(_ fallback: Color, _ keyPath: KeyPath<HUDThemePalette, NSColor>) -> Color {
        guard let raw = UserDefaults.standard.string(forKey: "hud.visualTheme"),
              let palette = HUDThemePalette.palette(raw) else { return fallback }
        return Color(palette[keyPath: keyPath])
    }

    static func themedColors(_ fallback: [Color], top: KeyPath<HUDThemePalette, NSColor>, bottom: KeyPath<HUDThemePalette, NSColor>) -> [Color] {
        guard let raw = UserDefaults.standard.string(forKey: "hud.visualTheme"),
              HUDThemePalette.palette(raw) != nil else { return fallback }
        return [themed(fallback[0], top), themed(fallback[min(1, fallback.count - 1)], bottom)]
    }

    static var cardGradient: [Color] {
        themedColors(classicCardGradient, top: \.cardTop, bottom: \.cardBottom)
    }

    static var filterBarGradient: [Color] {
        themedColors(classicFilterBarGradient, top: \.cardTop, bottom: \.windowMiddle)
    }

    static var footerGradient: [Color] {
        themedColors(classicFooterGradient, top: \.windowTop, bottom: \.windowBottom)
    }

    static var selectionGradient: [Color] {
        guard UserDefaults.standard.string(forKey: "hud.visualTheme") == "classic" ||
              HUDThemePalette.palette(UserDefaults.standard.string(forKey: "hud.visualTheme") ?? "") == nil else {
            return [accent.opacity(0.75), accent.opacity(0.42)]
        }
        return classicSelectionGradient
    }

    static var filterPillGradient: [Color] {
        themedColors(classicFilterPillGradient, top: \.cardTop, bottom: \.cardBottom)
    }

    static var brandGradient: [Color] {
        themedColors(classicBrandGradient, top: \.cardTop, bottom: \.windowMiddle)
    }

    static let accent = themed(adaptiveColor(
        light: rgb(0.19, 0.32, 0.76),
        dark: rgb(0.47, 0.60, 1.00)
    ), \.accent)
    static let selectionText = themed(adaptiveColor(
        light: rgb(0.16, 0.29, 0.70),
        dark: rgb(0.80, 0.86, 1.00)
    ), \.selectionText)
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
    static let classicCardGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.95),
            rgb(0.965, 0.975, 1.00, alpha: 0.88)
        ],
        dark: [
            rgb(0.075, 0.095, 0.165, alpha: 0.94),
            rgb(0.045, 0.060, 0.120, alpha: 0.91)
        ]
    )
    static var cardBorderGradient: [Color] {
        guard let palette else { return classicCardBorderGradient }
        return [Color(palette.border).opacity(0.8), Color(palette.border).opacity(0.32)]
    }

    static var glassSheen: Color {
        guard let palette else { return classicGlassSheen }
        return Color(palette.accent).opacity(0.08)
    }

    static var auroraSheen: Color {
        guard let palette else { return classicAuroraSheen }
        return Color(palette.accent).opacity(0.13)
    }

    static var borderStrong: Color {
        guard let palette else { return classicBorderStrong }
        return Color(palette.border).opacity(1.4)
    }

    static var controlFill: Color {
        guard let palette else { return classicControlFill }
        return Color(palette.textSecondary).opacity(0.10)
    }

    private static var palette: HUDThemePalette? {
        UserDefaults.standard.string(forKey: "hud.visualTheme").flatMap(HUDThemePalette.palette)
    }

    static let classicCardBorderGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.92),
            rgb(0.43, 0.52, 0.75, alpha: 0.14)
        ],
        dark: [
            rgb(0.48, 0.58, 0.88, alpha: 0.25),
            rgb(0.25, 0.34, 0.62, alpha: 0.10)
        ]
    )
    static let classicFilterBarGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.52),
            rgb(0.93, 0.95, 1.00, alpha: 0.36)
        ],
        dark: [
            rgb(0.070, 0.085, 0.170, alpha: 0.94),
            rgb(0.035, 0.050, 0.120, alpha: 0.94)
        ]
    )
    static let classicFilterPillGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.66),
            rgb(0.94, 0.96, 1.00, alpha: 0.48)
        ],
        dark: [
            rgb(0.12, 0.15, 0.25, alpha: 0.52),
            rgb(0.075, 0.095, 0.18, alpha: 0.42)
        ]
    )
    static let classicSelectionGradient = adaptiveColors(
        light: [
            rgb(0.68, 0.77, 1.00, alpha: 0.94),
            rgb(0.86, 0.90, 1.00, alpha: 0.88)
        ],
        dark: [
            rgb(0.17, 0.27, 0.62, alpha: 0.98),
            rgb(0.075, 0.11, 0.30, alpha: 0.98)
        ]
    )
    static let classicBrandGradient = adaptiveColors(
        light: [
            rgb(1.00, 1.00, 1.00, alpha: 0.96),
            rgb(0.93, 0.95, 1.00, alpha: 0.86)
        ],
        dark: [
            rgb(0.10, 0.15, 0.30, alpha: 0.98),
            rgb(0.055, 0.080, 0.19, alpha: 0.98)
        ]
    )
    static let classicFooterGradient = adaptiveColors(
        light: [
            rgb(0.96, 0.97, 1.00, alpha: 0.62),
            rgb(0.90, 0.93, 1.00, alpha: 0.82)
        ],
        dark: [
            rgb(0.040, 0.055, 0.120, alpha: 0.94),
            rgb(0.025, 0.035, 0.085, alpha: 0.98)
        ]
    )
    static let classicGlassSheen = adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.70),
        dark: rgb(0.30, 0.36, 0.78, alpha: 0.055)
    )
    static let classicAuroraSheen = adaptiveColor(
        light: rgb(0.48, 0.64, 1.00, alpha: 0.22),
        dark: rgb(0.25, 0.16, 0.70, alpha: 0.065)
    )
    static let surface = themed(adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.94),
        dark: rgb(0.070, 0.085, 0.125, alpha: 0.96)
    ), \.surface)
    static let surfaceRaised = themed(adaptiveColor(
        light: rgb(1.00, 1.00, 1.00, alpha: 0.99),
        dark: rgb(0.095, 0.115, 0.165, alpha: 0.98)
    ), \.surfaceRaised)
    static let classicControlFill = adaptiveColor(
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
    static let border = themed(adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.09),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    ), \.border)
    static let classicBorderStrong = adaptiveColor(
        light: NSColor(calibratedWhite: 0.025, alpha: 0.16),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.20)
    )
    static let divider = adaptiveColor(
        light: NSColor(calibratedWhite: 0.04, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.09)
    )
    static let textPrimary = themed(adaptiveColor(
        light: rgb(0.075, 0.085, 0.115),
        dark: rgb(0.94, 0.95, 0.985)
    ), \.textPrimary)
    static let textSecondary = themed(adaptiveColor(
        light: rgb(0.27, 0.30, 0.36),
        dark: rgb(0.73, 0.77, 0.85)
    ), \.textSecondary)
    static let textTertiary = themed(adaptiveColor(
        light: rgb(0.41, 0.44, 0.51),
        dark: rgb(0.58, 0.63, 0.73)
    ), \.textTertiary)
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
        light: rgb(0.82, 0.51, 0.04),
        dark: rgb(1.00, 0.76, 0.24)
    )
    static let pi = adaptiveColor(
        light: rgb(0.48, 0.28, 0.78),
        dark: rgb(0.75, 0.55, 1.00)
    )
    static let opencode = adaptiveColor(
        light: rgb(0.10, 0.55, 0.30),
        dark: rgb(0.32, 0.85, 0.49)
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
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
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
