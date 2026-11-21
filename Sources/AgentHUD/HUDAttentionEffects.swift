import AppKit
import QuartzCore
import SwiftUI

struct BreathingView<Content: View>: View {
    let minimum: Double
    let duration: Double
    @ViewBuilder let content: Content

    var body: some View {
        content.phaseAnimator([false, true]) { content, dimmed in
            content.opacity(dimmed ? minimum : 1)
        } animation: { _ in
            .easeInOut(duration: duration)
        }
    }
}

/// A single animated render-layer for border attention; no per-frame HUD redraw.
struct AttentionBorderLayer: NSViewRepresentable {
    let color: Color
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.3
    var marquee = false
    var minimumOpacity: Double = 0.22
    var duration: Double = 1.5

    func makeNSView(context: Context) -> AttentionBorderNSView {
        AttentionBorderNSView()
    }

    func updateNSView(_ nsView: AttentionBorderNSView, context: Context) {
        nsView.configure(
            color: NSColor(color).cgColor,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            marquee: marquee,
            minimumOpacity: minimumOpacity,
            duration: duration
        )
    }
}

final class AttentionBorderNSView: NSView {
    private let baseLayer = CAShapeLayer()
    private let laserLayer = CAShapeLayer()
    private var key = ""
    private var cornerRadius: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(baseLayer)
        layer?.addSublayer(laserLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        for shape in [baseLayer, laserLayer] {
            shape.frame = bounds
            shape.path = path
            shape.shadowPath = path
        }
        laserLayer.lineDashPattern = [42, 110]
        CATransaction.commit()
    }

    func configure(
        color: CGColor,
        cornerRadius: CGFloat,
        lineWidth: CGFloat,
        marquee: Bool,
        minimumOpacity: Double,
        duration: Double
    ) {
        self.cornerRadius = cornerRadius
        let nextKey = "\(color)-\(marquee)-\(minimumOpacity)-\(duration)"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.fillColor = nil
        baseLayer.strokeColor = color
        baseLayer.lineWidth = lineWidth
        baseLayer.shadowColor = color
        baseLayer.shadowRadius = marquee ? 6 : 4
        baseLayer.shadowOffset = .zero
        laserLayer.fillColor = nil
        laserLayer.strokeColor = color
        laserLayer.lineWidth = lineWidth + 0.8
        laserLayer.lineCap = .round
        laserLayer.shadowColor = color
        laserLayer.shadowRadius = 6
        laserLayer.shadowOffset = .zero
        laserLayer.opacity = marquee ? 1 : 0
        baseLayer.opacity = marquee ? 0.3 : 1
        CATransaction.commit()
        needsLayout = true
        guard key != nextKey else { return }
        key = nextKey
        baseLayer.removeAnimation(forKey: "hud.breathe")
        laserLayer.removeAnimation(forKey: "hud.marquee")
        if marquee {
            let animation = CABasicAnimation(keyPath: "lineDashPhase")
            animation.fromValue = 0
            animation.toValue = -152
            animation.duration = duration
            animation.repeatCount = .infinity
            laserLayer.add(animation, forKey: "hud.marquee")
        } else {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = minimumOpacity
            animation.toValue = 1
            animation.duration = duration
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            baseLayer.add(animation, forKey: "hud.breathe")
        }
    }
}

struct MarqueeBorder: View {
    let color: Color
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.6
    var duration: Double = 2.0

    var body: some View {
        AttentionBorderLayer(
            color: color,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            marquee: true,
            duration: duration
        )
    }
}

struct ProviderPreviewAnchor: NSViewRepresentable {
    let session: AgentSession?
    let title: String
    let summary: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard nsView.window?.isVisible == true else {
            context.coordinator.hide()
            return
        }
        if let session {
            context.coordinator.show(
                title: title,
                provider: session.provider.displayName,
                summary: summary,
                accent: NSColor(session.provider.accentColor),
                beside: nsView
            )
        } else {
            context.coordinator.hide()
        }
    }

    func makeCoordinator() -> ProviderPreviewController {
        ProviderPreviewController()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ProviderPreviewController) {
        coordinator.hide()
    }
}
