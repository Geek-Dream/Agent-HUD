import AppKit
import SwiftUI

enum HUDMetrics {
    static let collapsedWidth: CGFloat = 320
    static let collapsedHeight: CGFloat = 62
    static let panelGap: CGFloat = 18

    static let resizeDuration: TimeInterval = Motion.enterDuration
    // MARK: - Design tokens

    enum Radius {
        static let micro: CGFloat = 5
        static let control: CGFloat = 7
        static let small: CGFloat = 9
        static let card: CGFloat = 8
        static let panel: CGFloat = 18
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
        static let title = Font.system(size: 13.5, weight: .semibold)
        static let body = Font.system(size: 12)
        static let label = Font.system(size: 11, weight: .semibold)
        static let caption = Font.system(size: 11, weight: .medium)
        static let micro = Font.system(size: 9.5, weight: .semibold)
        static let agent = Font.system(size: 9, weight: .semibold, design: .monospaced)
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
        .spring(response: 0.32, dampingFraction: 0.82)
    }

    static var pageAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: Motion.pageDuration)
    }

    static var calloutAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.92)
    }

    static var listAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.28)
    }
}

extension AgentProvider {
    var symbolName: String {
        switch self {
        case .codex:
            return "diamond.fill"
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

struct SessionGlyphStyle {
    let symbol: String
    let color: Color

    var highlightColor: Color {
        switch symbol {
        case "chart.bar.fill":
            return HUDTheme.glyphPink
        case "storefront.fill":
            return HUDTheme.important
        case "bubble.left.and.bubble.right.fill", "paintpalette.fill", "sparkles":
            return HUDTheme.glyphViolet
        case "chevron.left.forwardslash.chevron.right", "doc.text.fill":
            return HUDTheme.glyphCyan
        case "diamond.fill", "circle.hexagongrid.fill":
            return HUDTheme.glyphCyan
        case "sparkle":
            return HUDTheme.important
        default:
            return color
        }
    }
}

enum SessionGlyphPolicy {
    static func style(title: String, provider: AgentProvider) -> SessionGlyphStyle {
        let text = title.lowercased()

        if containsAny(["sql", "api", "统计", "数据", "分析"], in: text) {
            return SessionGlyphStyle(symbol: "chart.bar.fill", color: HUDTheme.glyphViolet)
        }
        if containsAny(["端口", "服务", "重启", "部署"], in: text) {
            return SessionGlyphStyle(symbol: "storefront.fill", color: HUDTheme.glyphOrange)
        }
        if containsAny(["确认", "问题", "是否", "解决", "沟通"], in: text) {
            return SessionGlyphStyle(
                symbol: "bubble.left.and.bubble.right.fill",
                color: HUDTheme.glyphViolet
            )
        }
        if containsAny(["页面", "卡片", "模块", "代码", "前端", "组件"], in: text) {
            return SessionGlyphStyle(
                symbol: "chevron.left.forwardslash.chevron.right",
                color: HUDTheme.glyphMint
            )
        }
        if containsAny(["颜色", "样式", "背景", "视觉", "设计"], in: text) {
            return SessionGlyphStyle(symbol: "paintpalette.fill", color: HUDTheme.glyphPink)
        }
        if containsAny(["标题", "生成", "优化", "技能", "集成", "动画", "交互", "筛选"], in: text) {
            return SessionGlyphStyle(symbol: "sparkles", color: HUDTheme.glyphCyan)
        }
        if containsAny(["文档", "需求", "报告", "总结"], in: text) {
            return SessionGlyphStyle(symbol: "doc.text.fill", color: HUDTheme.glyphCyan)
        }

        return SessionGlyphStyle(symbol: provider.symbolName, color: provider.accentColor)
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

extension StatusFilter {
    var color: Color {
        switch self {
        case .all:
            return HUDTheme.accent
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

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .working:
            return "briefcase"
        case .waiting:
            return "clock"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        }
    }
}

extension ProviderFilter {
    var symbolName: String {
        provider?.symbolName ?? "rectangle.3.group"
    }

    var accentColor: Color {
        provider?.accentColor ?? HUDTheme.accent
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
