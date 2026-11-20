import AppKit
import Combine
import QuartzCore
import SwiftUI

@main
struct AgentHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AgentHUD", systemImage: "list.bullet.rectangle") {
            AgentHUDStatusMenu(model: appDelegate.model, appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = HUDViewModel()
    private var panel: FloatingPanel?
    private var subscriptions: Set<AnyCancellable> = []
    private var isUpdatingPanelSize = false
    private var linkServer: LinkServer?
    private var linkSettingsWindowController: LinkSettingsWindowController?
    private lazy var aiSettingsWindowController = AISettingsWindowController(
        displayModel: model,
        onConfigurationChanged: { [weak self] in
            self?.model.reloadAIConfiguration()
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if let previewAppearance = ProcessInfo.processInfo.environment["AGENTHUD_PREVIEW_APPEARANCE"] {
            NSApp.appearance = NSAppearance(
                named: previewAppearance == "dark" ? .darkAqua : .aqua
            )
        }
        #endif
        createPanel()
        bindPanelState()

        model.onHide = { [weak self] in
            self?.hidePanel()
        }
        model.onOpenAISettings = { [weak self] in
            self?.showAISettings()
        }
        model.start()
        do {
            let server = try LinkServer()
            linkServer = server
            linkSettingsWindowController = LinkSettingsWindowController(server: server)
            Task {
                do {
                    try await server.start(provider: model)
                } catch {
                    NSLog("AgentHUD LAN service failed: %@", error.localizedDescription)
                }
            }
        } catch {
            NSLog("AgentHUD LAN initialization failed: %@", error.localizedDescription)
        }

        DispatchQueue.main.async { [weak self] in
            self?.showPanel(activate: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        linkServer?.stop()
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func createPanel() {
        let initialSize = panelSize(expanded: model.isExpanded)
        let panel = FloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialSize.width,
                height: initialSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.hidesOnDeactivate = false
        panel.isMovable = !model.positionLocked
        panel.isMovableByWindowBackground = !model.positionLocked
        panel.animationBehavior = .utilityWindow
        panel.contentMinSize = model.isExpanded
            ? NSSize(
                width: ExpandedPanelSize.minimumWidth,
                height: ExpandedPanelSize.minimumHeight
            )
            : panelSize(expanded: false)
        panel.contentMaxSize = NSSize(
            width: ExpandedPanelSize.maximumWidth,
            height: ExpandedPanelSize.maximumHeight
        )

        let container = NSView(
            frame: NSRect(origin: .zero, size: initialSize)
        )
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.masksToBounds = true
        container.layer?.cornerRadius = HUDMetrics.Radius.panel
        container.layer?.cornerCurve = .continuous
        container.autoresizesSubviews = true

        let hostingView = NSHostingView(rootView: HUDShell(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        let restoredFrame = panel.setFrameUsingName("AgentHUD.FloatingPanel")
        if !restoredFrame {
            positionPanelAtDefaultLocation(panel)
        } else if abs(panel.frame.width - initialSize.width) > 1
                    || abs(panel.frame.height - initialSize.height) > 1 {
            positionPanelAtDefaultLocation(panel)
        }
        setPanelSize(initialSize, keepingTopTrailingAnchor: panel, display: false)
        panel.setFrameAutosaveName("AgentHUD.FloatingPanel")
        self.panel = panel
        updateTrafficLightVisibility()
    }

    private func bindPanelState() {
        model.$positionLocked
            .removeDuplicates()
            .sink { [weak self] locked in
                self?.panel?.isMovable = !locked
                self?.panel?.isMovableByWindowBackground = !locked
            }
            .store(in: &subscriptions)

        model.$isExpanded
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] expanded in
                self?.resizePanel(expanded: expanded)
                self?.updateTrafficLightVisibility()
            }
            .store(in: &subscriptions)

        Publishers.CombineLatest(model.$expandedWidth, model.$expandedHeight)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                guard let self,
                      self.model.isExpanded,
                      !self.isUpdatingPanelSize,
                      self.panel?.inLiveResize != true else {
                    return
                }
                self.resizePanel(expanded: true, animated: false)
            }
            .store(in: &subscriptions)
    }

    private func positionPanelAtDefaultLocation(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - HUDMetrics.panelGap,
            y: visible.maxY - size.height - HUDMetrics.panelGap
        )
        panel.setFrameOrigin(origin)
    }

    private func resizePanel(expanded: Bool, animated: Bool = true) {
        guard let panel else {
            return
        }

        panel.contentMinSize = expanded
            ? NSSize(
                width: ExpandedPanelSize.minimumWidth,
                height: ExpandedPanelSize.minimumHeight
            )
            : panelSize(expanded: false)
        let targetFrame = frame(
            for: panelSize(expanded: expanded),
            keepingTopTrailingAnchor: panel
        )
        guard animated else {
            panel.setFrame(targetFrame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDMetrics.resizeDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.16, 1.0, 0.3, 1.0
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func panelSize(expanded: Bool) -> NSSize {
        expanded
            ? NSSize(width: model.expandedWidth, height: model.expandedHeight)
            : NSSize(width: HUDMetrics.collapsedWidth, height: HUDMetrics.collapsedHeight)
    }

    private func frame(
        for size: NSSize,
        keepingTopTrailingAnchor panel: NSPanel
    ) -> NSRect {
        let oldFrame = panel.frame
        return NSRect(
            x: oldFrame.maxX - size.width,
            y: oldFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func setPanelSize(
        _ size: NSSize,
        keepingTopTrailingAnchor panel: NSPanel,
        display: Bool
    ) {
        panel.setFrame(
            frame(for: size, keepingTopTrailingAnchor: panel),
            display: display
        )
    }

    private func showPanel(activate: Bool) {
        guard let panel else {
            return
        }
        setPanelSize(
            panelSize(expanded: model.isExpanded),
            keepingTopTrailingAnchor: panel,
            display: false
        )
        keepPanelOnScreen(panel)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        updateTrafficLightVisibility()
        panel.orderFrontRegardless()
    }

    private func keepPanelOnScreen(_ panel: NSPanel) {
        guard let screen = panel.screen ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        guard visible.intersects(panel.frame) else {
            positionPanelAtDefaultLocation(panel)
            return
        }

        var origin = panel.frame.origin
        origin.x = min(
            max(origin.x, visible.minX + HUDMetrics.panelGap),
            visible.maxX - panel.frame.width - HUDMetrics.panelGap
        )
        origin.y = min(
            max(origin.y, visible.minY + HUDMetrics.panelGap),
            visible.maxY - panel.frame.height - HUDMetrics.panelGap
        )
        panel.setFrameOrigin(origin)
    }

    private func updateTrafficLightVisibility() {
        guard let panel else {
            return
        }
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = !model.isExpanded
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    func togglePanel() {
        guard let panel else {
            return
        }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel(activate: true)
        }
    }

    func toggleExpanded() {
        model.isExpanded.toggle()
        showPanel(activate: false)
    }

    func togglePrivacy() {
        model.togglePrivacy()
    }

    func refresh() {
        Task {
            await model.refresh()
        }
    }

    func showAISettings() {
        aiSettingsWindowController.present()
    }

    func showLinkSettings() {
        linkSettingsWindowController?.present()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

private struct AgentHUDStatusMenu: View {
    @ObservedObject var model: HUDViewModel
    let appDelegate: AppDelegate

    var body: some View {
        Button("显示或隐藏 AgentHUD") {
            appDelegate.togglePanel()
        }

        Button(model.isExpanded ? "收起面板" : "展开面板") {
            appDelegate.toggleExpanded()
        }

        Toggle(
            "隐私模式",
            isOn: Binding(
                get: { model.privacyMode },
                set: { model.privacyMode = $0 }
            )
        )

        Toggle(
            "锁定面板位置",
            isOn: Binding(
                get: { model.positionLocked },
                set: { model.positionLocked = $0 }
            )
        )

        Button("立即刷新") {
            appDelegate.refresh()
        }
        .keyboardShortcut("r")

        Button("手机关联…") {
            appDelegate.showLinkSettings()
        }

        Button("AI 标题与显示设置…") {
            appDelegate.showAISettings()
        }

        Divider()

        Button("退出 AgentHUD") {
            appDelegate.quit()
        }
        .keyboardShortcut("q")
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let panel,
              notification.object as? NSPanel === panel,
              model.isExpanded else {
            return
        }

        let size = panel.contentView?.bounds.size ?? panel.frame.size
        let width = ExpandedPanelSize.clampedWidth(size.width)
        let height = ExpandedPanelSize.clampedHeight(size.height)
        guard abs(width - model.expandedWidth) > 0.5
                || abs(height - model.expandedHeight) > 0.5 else {
            return
        }

        isUpdatingPanelSize = true
        model.expandedWidth = width
        model.expandedHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.isUpdatingPanelSize = false
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
