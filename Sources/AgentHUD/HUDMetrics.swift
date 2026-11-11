import AppKit
import SwiftUI

enum HUDMetrics {
    static let expandedWidth: CGFloat = 424
    static let expandedHeight: CGFloat = 620
    static let collapsedWidth: CGFloat = 320
    static let collapsedHeight: CGFloat = 62
    static let panelGap: CGFloat = 18
    static let resizeDuration: TimeInterval = 0.32
    static let contentExitDuration: TimeInterval = 0.14
    static let contentEnterDuration: TimeInterval = 0.24
    static let filterDuration: TimeInterval = 0.22
    static let pageDuration: TimeInterval = 0.18

    static var contentExitAnimation: Animation {
        .timingCurve(0.4, 0, 0.9, 0.45, duration: contentExitDuration)
    }

    static var contentEnterAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: contentEnterDuration)
    }

    static var filterAnimation: Animation {
        .spring(response: 0.32, dampingFraction: 0.9)
    }

    static var pageAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: pageDuration)
    }

    static var calloutAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.9)
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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
