import AppKit
import SwiftUI

@MainActor
final class ImagePreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = ImagePreviewWindowController()

    private var panel: ImagePreviewPanel?
    private var model: ImagePreviewModel?

    func show(images: [SessionImageAttachment], initialIndex: Int) {
        guard !images.isEmpty else {
            return
        }

        panel?.close()

        let model = ImagePreviewModel(images: images, initialIndex: initialIndex)
        let content = ImagePreviewView(model: model) { [weak self] in
            self?.panel?.close()
        }
        let hostingView = NSHostingView(rootView: content)
        let panel = ImagePreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "图片预览"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 520, height: 380)
        panel.contentView = hostingView
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in
            self?.handleKeyEvent(event) ?? false
        }

        self.model = model
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        model = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            panel?.close()
            return true
        }
        return model?.handleKeyEvent(event) ?? false
    }
}

@MainActor
private final class ImagePreviewModel: ObservableObject {
    let images: [SessionImageAttachment]
    @Published private(set) var selectedIndex: Int
    @Published private(set) var scale: CGFloat = 1
    private var gestureStartScale: CGFloat?

    init(images: [SessionImageAttachment], initialIndex: Int) {
        self.images = images
        selectedIndex = min(max(initialIndex, 0), max(images.count - 1, 0))
    }

    var selectedImage: SessionImageAttachment? {
        guard images.indices.contains(selectedIndex) else {
            return nil
        }
        return images[selectedIndex]
    }

    var counterLabel: String {
        "[图片 \(selectedIndex + 1) / \(images.count)]"
    }

    func previous() {
        guard images.count > 1 else {
            return
        }
        selectedIndex = selectedIndex == 0 ? images.count - 1 : selectedIndex - 1
    }

    func next() {
        guard images.count > 1 else {
            return
        }
        selectedIndex = selectedIndex == images.count - 1 ? 0 : selectedIndex + 1
    }

    func zoomIn() {
        setScale(scale + 0.25)
    }

    func zoomOut() {
        setScale(scale - 0.25)
    }

    func resetZoom() {
        scale = 1
    }

    func setScale(_ value: CGFloat) {
        scale = min(max(value, 0.5), 4)
    }

    func updateMagnification(_ value: CGFloat) {
        if gestureStartScale == nil {
            gestureStartScale = scale
        }
        setScale((gestureStartScale ?? scale) * value)
    }

    func endMagnification(_ value: CGFloat) {
        setScale((gestureStartScale ?? scale) * value)
        gestureStartScale = nil
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            previous()
            return true
        case 124:
            next()
            return true
        case 24, 69:
            zoomIn()
            return true
        case 27, 78:
            zoomOut()
            return true
        case 29:
            resetZoom()
            return true
        default:
            break
        }

        switch event.charactersIgnoringModifiers {
        case "+", "=":
            zoomIn()
            return true
        case "-", "_":
            zoomOut()
            return true
        case "0":
            resetZoom()
            return true
        default:
            return false
        }
    }
}

private final class ImagePreviewPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private struct ImagePreviewView: View {
    @ObservedObject var model: ImagePreviewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.5)
            imageStage
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 520, minHeight: 380)
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(model.counterLabel)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()

            Spacer()

            PreviewToolbarButton(symbol: "minus.magnifyingglass", help: "缩小") {
                model.zoomOut()
            }

            Text("\(Int((model.scale * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42)
                .monospacedDigit()

            PreviewToolbarButton(symbol: "plus.magnifyingglass", help: "放大") {
                model.zoomIn()
            }

            PreviewToolbarButton(symbol: "arrow.counterclockwise", help: "重置缩放") {
                model.resetZoom()
            }

            PreviewToolbarButton(symbol: "xmark", help: "关闭预览", action: onClose)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.ultraThinMaterial)
    }

    private var imageStage: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                imageContent
                    .scaleEffect(model.scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged(model.updateMagnification)
                            .onEnded(model.endMagnification)
                    )
                    .padding(30)

                HStack(spacing: 0) {
                    clickZone(
                        symbol: "chevron.left",
                        width: max(58, proxy.size.width * 0.14),
                        help: "上一张",
                        action: model.previous
                    )

                    Spacer()

                    clickZone(
                        symbol: "chevron.right",
                        width: max(58, proxy.size.width * 0.14),
                        help: "下一张",
                        action: model.next
                    )
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let source = model.selectedImage?.source,
           let image = SessionImageCache.image(for: source) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 34, weight: .light))
                Text("这张图片暂时无法读取")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func clickZone(
        symbol: String,
        width: CGFloat,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Color.clear
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.72))
                    .frame(width: 34, height: 42)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct PreviewToolbarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 27, height: 27)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
