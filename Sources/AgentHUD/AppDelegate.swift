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
    private lazy var aiSettingsWindowController = AISettingsWindowController {
        [weak self] in
        self?.model.reloadAIConfiguration()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        bindPanelState()

        model.onHide = { [weak self] in
            self?.hidePanel()
        }
        model.onOpenAISettings = { [weak self] in
            self?.showAISettings()
        }
        model.start()

        DispatchQueue.main.async { [weak self] in
            self?.showPanel(activate: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
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
        panel.contentMinSize = panelSize(expanded: false)
        panel.contentMaxSize = panelSize(expanded: true)

        let container = NSView(
            frame: NSRect(origin: .zero, size: initialSize)
        )
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.cornerRadius = 14
        container.layer?.cornerCurve = .continuous
        container.autoresizesSubviews = true

        let hostingView = NSHostingView(rootView: HUDShell(model: model))
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        panel.contentView = container

        if !panel.setFrameUsingName("AgentHUD.FloatingPanel") {
            positionPanelAtDefaultLocation(panel)
        }
        setPanelSize(initialSize, keepingTopTrailingAnchor: panel, display: false)
        panel.setFrameAutosaveName("AgentHUD.FloatingPanel")
        self.panel = panel
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

    private func resizePanel(expanded: Bool) {
        guard let panel else {
            return
        }

        let targetFrame = frame(
            for: panelSize(expanded: expanded),
            keepingTopTrailingAnchor: panel
        )
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
            ? NSSize(width: HUDMetrics.expandedWidth, height: HUDMetrics.expandedHeight)
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
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.orderFrontRegardless()
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

        Button("AI 标题设置…") {
            appDelegate.showAISettings()
        }

        Divider()

        Button("退出 AgentHUD") {
            appDelegate.quit()
        }
        .keyboardShortcut("q")
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
