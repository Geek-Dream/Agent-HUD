import AppKit
import SwiftUI

@MainActor
final class ProviderPreviewController: NSObject {
    private var window: NSPanel?
    private var contentKey = ""

    func show(title: String, provider: String, summary: String, accent: NSColor, beside sourceView: NSView) {
        guard let sourceWindow = sourceView.window,
              let screen = sourceWindow.screen else { return }
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 292, height: 150),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            window = panel
        }
        guard let panel = window else { return }
        let nextKey = "\(title)-\(provider)-\(summary)-\(accent)"
        if contentKey != nextKey {
            contentKey = nextKey
            panel.contentView = NSHostingView(rootView: ProviderPreviewView(
                title: title,
                provider: provider,
                summary: summary,
                accent: Color(accent)
            ))
        }
        let sourceRect = sourceView.convert(sourceView.bounds, to: nil)
        let screenRect = sourceWindow.convertToScreen(sourceRect)
        let width: CGFloat = 292
        let x = max(screen.visibleFrame.minX + 8, screenRect.minX - width - 12)
        let y = min(max(screenRect.midY - 76, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - 160)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: 152), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {        window?.orderOut(nil)
    }
}

private struct ProviderPreviewView: View {
    let title: String
    let provider: String
    let summary: String
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(accent)
                    Text("\(provider) · 星标任务完成")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .lineLimit(4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(accent.opacity(0.55), lineWidth: 1)
            }
            Rectangle()
                .fill(accent.opacity(0.7))
                .frame(width: 12, height: 1)
        }
        .frame(width: 292, height: 152)
        .shadow(color: accent.opacity(0.22), radius: 12, y: 4)
    }
}
