import AppKit
import SwiftUI

enum HUDMetrics {
    static let collapsedWidth: CGFloat = 320
    static let collapsedHeight: CGFloat = 62
    static let panelGap: CGFloat = 18

    static let resizeDuration: TimeInterval = Motion.enterDuration
    // MARK: - Design tokens

    enum Radius {
        static let micro: CGFloat = 4
        static let control: CGFloat = 7
        static let small: CGFloat = 8
        static let card: CGFloat = 10
        static let panel: CGFloat = 14
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
    }

    enum Typography {
        static let display = Font.system(size: 20, weight: .semibold)
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12)
        static let label = Font.system(size: 11, weight: .semibold)
        static let caption = Font.system(size: 10.5, weight: .medium)
        static let micro = Font.system(size: 9.5, weight: .semibold)
        static let agent = Font.system(size: 8.5, weight: .bold, design: .monospaced)
    }

    enum Motion {
        static let enterDuration: TimeInterval = 0.32
        static let exitDuration: TimeInterval = 0.14
        static let stateDuration: TimeInterval = 0.30
        static let pageDuration: TimeInterval = 0.18
    }

    // MARK: - Shared animations

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func motion(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    static var contentExitAnimation: Animation {
        .timingCurve(0.4, 0, 0.9, 0.45, duration: Motion.exitDuration)
    }

    static var contentEnterAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: Motion.enterDuration)
    }

    static var filterAnimation: Animation {
        .spring(response: Motion.stateDuration, dampingFraction: 0.92)
    }

    static var pageAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: Motion.pageDuration)
    }

    static var calloutAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.92)
    }

    static var listAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.92)
    }
}

extension AgentProvider {
    var symbolName: String {
        switch self {
        case .codex:
            return "terminal.fill"
        case .claude:
            return "sparkle"
        case .pi:
            return "circle.hexagongrid.fill"
        case .opencode:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    var accentColor: Color {
        switch self {
        case .codex:
            return HUDTheme.codex
        case .claude:
            return HUDTheme.claude
        case .pi:
            return HUDTheme.pi
        case .opencode:
            return HUDTheme.opencode
        }
    }
}

extension StatusFilter {
    var color: Color {
        switch self {
        case .all:
            return HUDTheme.textPrimary
        case .working:
            return AgentStatus.working.color
        case .waiting:
            return AgentStatus.waitingUser.color
        case .completed:
            return AgentStatus.completed.color
        case .failed:
            return AgentStatus.failed.color
        }
    }
}

extension ProviderFilter {
    var symbolName: String {
        provider?.symbolName ?? "rectangle.3.group"
    }

    var accentColor: Color {
        provider?.accentColor ?? HUDTheme.textPrimary
    }
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .starting, .working:
            return HUDTheme.working
        case .waitingUser:
            return HUDTheme.waiting
        case .completed:
            return HUDTheme.completed
        case .failed:
            return HUDTheme.failed
        case .idle:
            return HUDTheme.textSecondary
        case .unknown:
            return HUDTheme.textTertiary
        }
    }

    var symbolName: String {
        switch self {
        case .starting:
            return "circle.dotted"
        case .working:
            return "waveform.path.ecg"
        case .waitingUser:
            return "questionmark.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "pause.circle"
        case .unknown:
            return "ellipsis.circle"
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var opacity: CGFloat = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.alphaValue = opacity
    }
}
