import AppKit
import Combine
import QuartzCore
import SwiftUI

struct HUDShell: View {
    @ObservedObject var model: HUDViewModel
    @ObservedObject private var runPagination = SessionRunPagination()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                background

                Group {
                    if let session = model.selectedSession {
                        SessionDetailView(
                            model: model,
                            session: session,
                            runPagination: runPagination
                        )
                        .transition(pageTransition)
                    } else {
                        ExpandedHUDView(model: model)
                            .transition(pageTransition)
                    }
                }
                .frame(
                    width: model.expandedWidth,
                    height: model.expandedHeight,
                    alignment: .topTrailing
                )
                .opacity(model.isExpanded ? 1 : 0)
                .offset(y: model.isExpanded ? 0 : -2)
                .animation(
                    model.isExpanded
                        ? HUDMetrics.contentEnterAnimation
                        : HUDMetrics.contentExitAnimation,
                    value: model.isExpanded
                )
                .allowsHitTesting(model.isExpanded)
                .animation(HUDMetrics.motion(HUDMetrics.pageAnimation), value: model.selectedSessionID)

                CollapsedHUDView(model: model)
                    .frame(
                        width: HUDMetrics.collapsedWidth,
                        height: HUDMetrics.collapsedHeight,
                        alignment: .topTrailing
                    )
                    .opacity(model.isExpanded ? 0 : 1)
                    .offset(y: model.isExpanded ? -2 : 0)
                    .animation(
                        model.isExpanded
                            ? HUDMetrics.contentExitAnimation
                            : HUDMetrics.contentEnterAnimation,
                        value: model.isExpanded
                    )
                    .allowsHitTesting(!model.isExpanded)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.panel, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                HUDTheme.borderStrong,
                                HUDTheme.border
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipped()
            .contrast(model.panelContrast)
        }
        .preferredColorScheme(nil)
        .ignoresSafeArea()
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: 18))
                .combined(with: .scale(scale: 0.98, anchor: .topTrailing)),
            removal: .opacity
                .combined(with: .offset(x: -10))
                .combined(with: .scale(scale: 0.99, anchor: .topTrailing))
        )
    }

    private var background: some View {
        Group {
            switch model.visualTheme {
            case .starlight:
                StarlightBackground(opacity: model.panelOpacity)
            case .classic:
                classicBackground
            }
        }
    }

    private var classicBackground: some View {
        ZStack {
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                opacity: 0.45
            )
            LinearGradient(
                colors: HUDTheme.windowGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(model.panelOpacity)
            .overlay {
                RadialGradient(
                    colors: [
                        HUDTheme.auroraSheen,
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.10, y: 0.02),
                    startRadius: 8,
                    endRadius: 520
                )
                .blendMode(.screen)
            }
            .overlay {
                PanelLightSweep()
            }
        }
    }
}

private struct PanelLightSweep: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.03))
                    path.addLine(to: CGPoint(x: width * 0.66, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: height * 0.30))
                    path.closeSubpath()
                }
                .fill(HUDTheme.glassSheen)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.20, y: 0))
                    path.addLine(to: CGPoint(x: width * 0.92, y: 0))
                    path.addLine(to: CGPoint(x: width * 0.30, y: height * 0.35))
                    path.closeSubpath()
                }
                .fill(HUDTheme.glassSheen.opacity(0.42))
                .blur(radius: 8)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width * 0.88, y: height))
                    path.addLine(to: CGPoint(x: width, y: height * 0.88))
                    path.addLine(to: CGPoint(x: 0, y: height * 0.98))
                    path.closeSubpath()
                }
                .fill(HUDTheme.glassSheen.opacity(0.55))
                .blur(radius: 5)
            }
            .allowsHitTesting(false)
        }
    }
}

@MainActor
private final class SessionRunPagination: ObservableObject {
    @Published private(set) var visibleCount = RunPagination.pageSize

    func reset() {
        visibleCount = RunPagination.pageSize
    }

    func loadMore(total: Int) {
        visibleCount = RunPagination.nextCount(current: visibleCount, total: total)
    }
}

private struct CollapsedHUDView: View {
    @ObservedObject var model: HUDViewModel

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 8) {
                BrandToggleButton(isExpanded: false) {
                    model.expand()
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        CompactMetric(
                            symbol: "waveform.path.ecg",
                            color: AgentStatus.working.color,
                            value: model.workingCount
                        )
                        CompactMetric(
                            symbol: "questionmark",
                            color: AgentStatus.waitingUser.color,
                            value: model.waitingCount
                        )
                        CompactMetric(
                            symbol: "checkmark",
                            color: AgentStatus.completed.color,
                            value: model.completedCount
                        )
                        if model.failedCount > 0 {
                            CompactMetric(
                                symbol: "exclamationmark",
                                color: AgentStatus.failed.color,
                                value: model.failedCount
                            )
                        }
                    }

                    Text(model.privacyMode ? "隐私模式已开启" : model.compactStatusText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .allowsHitTesting(false)
            }
            .layoutPriority(1)

            Spacer(minLength: 2)

            HUDIconButton(
                symbol: model.positionLocked ? "pin.fill" : "pin",
                help: model.positionLocked ? "解锁位置" : "锁定位置",
                tint: model.positionLocked ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePositionLock()
            }

            HUDIconButton(
                symbol: model.privacyMode ? "eye.slash.fill" : "eye",
                help: model.privacyMode ? "关闭隐私模式" : "开启隐私模式",
                tint: model.privacyMode ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePrivacy()
            }

            HUDIconButton(symbol: "gearshape", help: "AI 标题与显示设置") {
                model.openAISettings()
            }

            HUDIconButton(symbol: "xmark", help: "隐藏到菜单栏") {
                model.hide()
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            WindowDragHandle(isEnabled: !model.positionLocked)
        }
        .help(model.positionLocked ? "位置已锁定" : "拖动任意表头区域移动")
    }
}

private struct ExpandedHUDView: View {
    @ObservedObject var model: HUDViewModel

    var body: some View {
        let rows = model.visibleSessionRows
        return VStack(spacing: 0) {
            expandedHeader

            if model.privacyMode {
                PrivacyStrip()
            }

            filterSurface
                .zIndex(model.shouldShowImportantCompletionNotice ? 10 : 0)

            Group {
                if model.isLoading && model.sessions.isEmpty {
                    LoadingState()
                } else if rows.isEmpty {
                    EmptyState(
                        statusFilter: model.statusFilter,
                        providerFilter: model.providerFilter
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(rows) { row in
                                AgentRowView(
                                    model: model,
                                    session: row.session,
                                    phase: row.phase,
                                    arrivalVisible: row.arrivalVisible
                                ) {
                                    withAnimation(HUDMetrics.pageAnimation) {
                                        model.select(row.session)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                        .animation(
                            HUDMetrics.listAnimation,
                            value: rows.map(\.id)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                BrandToggleButton(isExpanded: true) {
                    model.collapse()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("AGENT HUD")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HUDTheme.textPrimary)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.activeCount > 0 ? HUDTheme.completed : HUDTheme.textTertiary)
                            .frame(width: 6, height: 6)
                        Text(model.activeCount > 0 ? "\(model.activeCount) 个 Agent 正在运行" : "本地只读监视中")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(HUDTheme.textSecondary)
                }
                .allowsHitTesting(false)
            }
            .layoutPriority(1)

            Spacer()

            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                HUDIconButton(symbol: "arrow.clockwise", help: "立即刷新") {
                    Task {
                        await model.refresh()
                    }
                }
            }

            HUDIconButton(
                symbol: model.positionLocked ? "pin.fill" : "pin",
                help: model.positionLocked ? "解锁位置" : "锁定位置",
                tint: model.positionLocked ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePositionLock()
            }

            HUDIconButton(
                symbol: model.privacyMode ? "eye.slash.fill" : "eye",
                help: model.privacyMode ? "关闭隐私模式" : "开启隐私模式",
                tint: model.privacyMode ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePrivacy()
            }

            HUDIconButton(symbol: "xmark", help: "隐藏到菜单栏") {
                model.hide()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 32)
        .padding(.bottom, 14)
        .background {
            WindowDragHandle(isEnabled: !model.positionLocked)
        }
        .help(model.positionLocked ? "位置已锁定" : "拖动任意表头区域移动")
    }

    private var filterSurface: some View {
        VStack(spacing: 0) {
            OverviewStrip(
                selectedFilter: model.statusFilter,
                highlightAll: model.shouldShowImportantCompletionNotice,
                count: { filter in
                    model.statusCount(filter)
                },
                onSelect: { filter in
                    withAnimation(HUDMetrics.filterAnimation) {
                        model.statusFilter = filter
                    }
                }
            )

            ProviderFilterStrip(
                selectedFilter: model.providerFilter,
                highlightAll: model.shouldShowImportantCompletionNotice,
                count: { filter in
                    model.providerCount(filter)
                },
                onSelect: { filter in
                    withAnimation(HUDMetrics.filterAnimation) {
                        model.providerFilter = filter
                    }
                }
            )
        }
        .overlay(alignment: .topLeading) {
            if model.shouldShowImportantCompletionNotice,
               let notice = model.importantCompletionNotice {
                ImportantCompletionCallout(
                    notice: notice,
                    privacyMode: model.privacyMode,
                    onReveal: {
                        withAnimation(HUDMetrics.pageAnimation) {
                            model.revealImportantCompletionNotice()
                        }
                    },
                    onDismiss: {
                        withAnimation(HUDMetrics.calloutAnimation) {
                            model.dismissImportantCompletionNotice()
                        }
                    }
                )
                .frame(width: model.expandedWidth - 18, alignment: .leading)
                .padding(.leading, 9)
                .offset(y: 44)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -10)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.97, anchor: .topLeading)),
                        removal: .offset(y: -5)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.985, anchor: .topLeading))
                    )
                )
                .zIndex(20)
            }
        }
        .animation(
            HUDMetrics.calloutAnimation,
            value: model.shouldShowImportantCompletionNotice
        )
        .background(Color.clear)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Button {
                model.openAISettings()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 10))
                    Text(model.visibleSessionSummary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("修改会话显示数量；星标会话始终常驻")

            if !model.dismissedSessionIDs.isEmpty {
                Button {
                    withAnimation(HUDMetrics.listAnimation) {
                        model.restoreAllDismissed()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                        Text("恢复已删除 \(model.dismissedSessionIDs.count)")
                            .monospacedDigit()
                    }
                    .foregroundStyle(HUDTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("把已删除的会话全部恢复显示")
                .accessibilityLabel("恢复已删除的 \(model.dismissedSessionIDs.count) 条会话")
                .transition(.opacity)
            }

            Spacer()
            if let scannedAt = model.lastScannedAt {
                HStack(spacing: 6) {
                    Circle()
                        .fill(HUDTheme.completed)
                        .frame(width: 5, height: 5)
                    Text("更新于 \(scannedAt.clockTime)")
                        .monospacedDigit()
                }
            } else {
                Text("正在读取")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(HUDTheme.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(
            LinearGradient(
                colors: HUDTheme.footerGradient,
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HUDTheme.border.opacity(0.7))
                .frame(height: 0.6)
        }
        .animation(HUDMetrics.listAnimation, value: model.dismissedSessionIDs.count)
    }
}

private struct SessionDetailView: View {
    @ObservedObject var model: HUDViewModel
    let session: AgentSession
    @ObservedObject var runPagination: SessionRunPagination

    private var sortedRuns: [TaskRun] {
        session.runs.sorted { $0.completedAt > $1.completedAt }
    }

    private var visibleRuns: [TaskRun] {
        Array(sortedRuns.prefix(runPagination.visibleCount))
    }

    private var hasMoreRuns: Bool {
        visibleRuns.count < sortedRuns.count
    }

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    identitySection
                    Divider().padding(.horizontal, 15)
                    progressSection
                    Divider().padding(.horizontal, 15)
                    userPromptSection
                    Divider().padding(.horizontal, 15)
                    summarySection
                }
            }

            detailFooter
        }
        .onAppear {
            runPagination.reset()
            expandUserPromptIfNeeded()
        }
        .onChange(of: session.id) { _, _ in
            model.cancelTitleEditing()
            runPagination.reset()
            expandUserPromptIfNeeded()
        }
    }

    private func expandUserPromptIfNeeded() {
        guard session.latestUserPrompt != nil,
              !model.isUserPromptExpanded(for: session) else {
            return
        }
        model.toggleUserPromptExpansion(for: session)
    }

    private var detailHeader: some View {
        HStack(spacing: 7) {
            HUDDragHandle(positionLocked: model.positionLocked)

            HUDIconButton(symbol: "chevron.left", help: "返回会话列表") {
                withAnimation(HUDMetrics.pageAnimation) {
                    model.showList()
                }
            }

            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                        .fill(session.provider.accentColor.opacity(0.13))
                    Image(systemName: session.provider.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(session.provider.accentColor)
                }
                .frame(width: 27, height: 27)

                Text(session.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))

                StatusBadge(status: session.status, confidence: session.confidence)
            }
            .allowsHitTesting(false)

            Spacer()

            HUDIconButton(
                symbol: model.isImportant(session) ? "star.fill" : "star",
                help: model.isImportant(session) ? "取消重要" : "标记为重要并置顶",
                tint: model.isImportant(session) ? importantTint : HUDTheme.textSecondary
            ) {
                withAnimation(HUDMetrics.filterAnimation) {
                    model.toggleImportance(for: session)
                }
            }

            HUDIconButton(
                symbol: model.positionLocked ? "pin.fill" : "pin",
                help: model.positionLocked ? "解锁位置" : "锁定位置",
                tint: model.positionLocked ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePositionLock()
            }

            HUDIconButton(
                symbol: model.privacyMode ? "eye.slash.fill" : "eye",
                help: model.privacyMode ? "关闭隐私模式" : "开启隐私模式",
                tint: model.privacyMode ? AgentStatus.waitingUser.color : HUDTheme.textSecondary
            ) {
                model.togglePrivacy()
            }

            HUDIconButton(symbol: "chevron.up", help: "收起") {
                model.collapse()
            }

            HUDIconButton(symbol: "xmark", help: "隐藏到菜单栏") {
                model.hide()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .padding(.top, 30)
        .background {
            WindowDragHandle(isEnabled: !model.positionLocked)
        }
        .help(model.positionLocked ? "位置已锁定" : "拖动任意表头区域移动")
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.privacyMode {
                Text("任务标题已隐藏")
                    .font(HUDMetrics.Typography.display)
                    .lineLimit(2)
            } else if model.editingTitleSessionID == session.id {
                titleEditor
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.displayTitle(for: session))
                        .font(HUDMetrics.Typography.display)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Spacer(minLength: 8)

                    if model.hoveredSessionID == session.id {
                        Button {
                            model.beginTitleEditing(for: session)
                        } label: {
                            Image(systemName: "pencil")
                                .font(HUDMetrics.Typography.label)
                                .foregroundStyle(HUDTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    HUDTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("编辑标题备注")
                        .accessibilityLabel("编辑标题备注")
                        .transition(.opacity.combined(with: .scale(scale: 0.86)))
                    }
                }
                .onHover { hovered in
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)) {
                        model.setHoveredSession(session.id, hovered: hovered)
                    }
                }

                HStack(spacing: 6) {
                    Image(
                        systemName: model.titleSource(for: session) == .user
                            ? "person.crop.circle"
                            : "sparkles"
                    )
                    .font(HUDMetrics.Typography.micro)

                    Text(model.titleSource(for: session).label)
                        .font(HUDMetrics.Typography.caption)

                    if model.hasCustomTitle(for: session) {
                        Text("·")
                        Button("恢复自动标题") {
                            model.clearCustomTitle(for: session)
                        }
                        .buttonStyle(.plain)
                        .font(HUDMetrics.Typography.caption)
                        .foregroundStyle(AgentStatus.working.color)
                        .help("清除手动备注，恢复自动概括标题")
                    }
                }
                .foregroundStyle(HUDTheme.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                Text(model.privacyMode ? "项目路径已隐藏" : abbreviatedPath(session.projectPath))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !model.privacyMode {
                    Button {
                        model.openProject(session)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中打开项目")
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(HUDTheme.textSecondary)

            HStack(spacing: 9) {
                if let git = session.git {
                    DetailFact(
                        symbol: "point.3.connected.trianglepath.dotted",
                        text: model.privacyMode ? "分支已隐藏" : git.branch
                    )
                    DetailFact(
                        symbol: "doc.on.doc",
                        text: "\(git.changedFiles) 个改动"
                    )
                    if git.insertions > 0 || git.deletions > 0 {
                        Text("+\(git.insertions) −\(git.deletions)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                } else {
                    DetailFact(symbol: "folder.badge.questionmark", text: "非 Git 项目")
                }

                Spacer()

                Text(session.lastActivityAt.relativeShort)
                    .font(.system(size: 10.5))
                        .foregroundStyle(HUDTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 15)
    }

    private var titleEditor: some View {
        HStack(spacing: 7) {
            TextField(
                "例如：日志查询",
                text: Binding(
                    get: { model.titleDraft },
                    set: { model.titleDraft = $0 }
                )
            )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    HUDTheme.controlFill,
                    in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                        .strokeBorder(HUDTheme.borderStrong, lineWidth: 0.8)
                }
                .onSubmit {
                    model.saveTitleEditing(for: session)
                }

            HUDIconButton(symbol: "checkmark", help: "保存标题备注", tint: AgentStatus.completed.color) {
                model.saveTitleEditing(for: session)
            }

            HUDIconButton(symbol: "xmark", help: "取消编辑") {
                model.cancelTitleEditing()
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "当前进度", symbol: session.status.symbolName)
                Spacer()
                Text("\(session.duration.compactDuration) · \(session.confidence.label)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(HUDTheme.textTertiary)
            }

            Text(model.privacyMode ? "当前动作已隐藏" : session.currentAction)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !model.privacyMode, !session.currentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(session.currentFiles.prefix(3)), id: \.self) { path in
                        HStack(spacing: 7) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text(relativeFile(path, projectPath: session.projectPath))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(HUDTheme.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private var userPromptSection: some View {
        let expanded = model.isUserPromptExpanded(for: session)
        let prompt = session.latestUserPrompt

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(HUDMetrics.pageAnimation) {
                    model.toggleUserPromptExpansion(for: session)
                }
            } label: {
                HStack(spacing: 8) {
                    SectionTitle(title: "用户原始输入", symbol: "text.bubble")

                    if let prompt, !prompt.images.isEmpty {
                        Label("\(prompt.images.count)", systemImage: "photo")
                            .font(HUDMetrics.Typography.micro)
                            .foregroundStyle(HUDTheme.textTertiary)
                    }

                    Spacer()

                    if let sentAt = prompt?.sentAt {
                        Text(sentAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.system(size: 10))
                            .foregroundStyle(HUDTheme.textTertiary)
                            .monospacedDigit()
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(HUDMetrics.Typography.micro)
                        .foregroundStyle(HUDTheme.textSecondary)
                        .frame(width: 18, height: 18)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if expanded {
                Group {
                    if model.privacyMode {
                        HStack(spacing: 7) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 10))
                            Text("隐私模式已隐藏原始输入与图片")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(AgentStatus.waitingUser.color)
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .background(
                            AgentStatus.waitingUser.color.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                        )
                    } else if let prompt,
                              !prompt.text.isEmpty || !prompt.images.isEmpty {
                        VStack(alignment: .leading, spacing: 11) {
                            if !prompt.text.isEmpty {
                                Text(prompt.text)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2.5)
                                    .textSelection(.enabled)
                            } else {
                                Text("这条消息只包含图片")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(HUDTheme.textSecondary)
                            }

                            if !prompt.images.isEmpty {
                                PromptImageGallery(images: prompt.images)
                            }
                        }
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 10))
                            Text("尚未读取到最近一次用户输入")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(HUDTheme.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .background(
                            HUDTheme.controlFill,
                            in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(HUDTheme.surface.opacity(0.18))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(title: "完成记录", symbol: "checklist")
                Spacer()
                Text("\(sortedRuns.count) 轮")
                    .font(.system(size: 10.5))
                    .foregroundStyle(HUDTheme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 3)

            if sortedRuns.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(HUDTheme.textTertiary)
                    Text("还没有完成记录")
                        .font(.system(size: 13, weight: .medium))
                    Text("当前任务结束后，本地摘要会出现在这里。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            } else {
                ForEach(visibleRuns) { run in
                    TaskRunView(
                        run: run,
                        privacyMode: model.privacyMode,
                        projectPath: session.projectPath
                    )
                    if run.id != visibleRuns.last?.id {
                        Divider()
                            .padding(.leading, 38)
                            .opacity(0.4)
                    }
                }

                if hasMoreRuns {
                    Button {
                        withAnimation(HUDMetrics.pageAnimation) {
                            runPagination.loadMore(total: sortedRuns.count)
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Rectangle()
                                .fill(HUDTheme.border)
                                .frame(height: 1)

                            Image(systemName: "chevron.down")
                                .font(HUDMetrics.Typography.micro)
                                .foregroundStyle(HUDTheme.textSecondary)

                            Rectangle()
                                .fill(HUDTheme.border)
                                .frame(height: 1)
                        }
                        .frame(height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .help("再加载 5 条完成记录")
                    .accessibilityLabel("再加载 5 条完成记录")
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var detailFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 10))
            Text("本地规则摘要 · 未修改 Agent 数据")
            Spacer()
            Text(model.privacyMode ? "隐私模式" : "只读")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(HUDTheme.textSecondary)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }
}

@MainActor
private final class RowMotionState: ObservableObject {
    @Published var hoverLocation: CGPoint?
    @Published var importantBurst = false
    private var burstSequence = 0

    func playImportantBurst() {
        burstSequence += 1
        let sequence = burstSequence
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            importantBurst = true
        }
        // Give SwiftUI one rendered frame at the bright, contracted state before
        // expanding the ring. This also survives the row moving to the top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.burstSequence == sequence else {
                return
            }
            withAnimation(.easeOut(duration: 0.60)) {
                self.importantBurst = false
            }
        }
    }

    func cancelImportantBurst() {
        burstSequence += 1
        importantBurst = false
    }
}

private struct AgentRowView: View {
    @ObservedObject var model: HUDViewModel
    @StateObject private var motion = RowMotionState()
    let session: AgentSession
    let phase: SessionRowPresentation.Phase
    let arrivalVisible: Bool
    let onOpen: () -> Void

    private var isEditingTitle: Bool {
        model.editingTitleSessionID == session.id
    }

    private var isHovered: Bool {
        model.hoveredSessionID == session.id
    }

    private var isImportant: Bool {
        model.isImportant(session)
    }

    private var glyphStyle: SessionGlyphStyle {
        SessionGlyphPolicy.style(
            title: model.privacyMode ? "" : model.displayTitle(for: session),
            provider: session.provider
        )
    }

    private var rowAccent: Color {
        isImportant ? importantTint : glyphStyle.color
    }

    private var showsEdgeLight: Bool {
        isHovered || isImportant || session.status.isRunning
    }

    private var isDeparting: Bool {
        phase == .departing
    }

    private var isArriving: Bool {
        phase == .arriving
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                glyphStyle.highlightColor.opacity(0.28),
                                glyphStyle.color.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                            .strokeBorder(glyphStyle.color.opacity(isHovered ? 0.58 : 0.28), lineWidth: 0.8)
                    }
                    .shadow(
                        color: glyphStyle.color.opacity(isHovered ? 0.48 : 0.16),
                        radius: isHovered ? 10 : 5,
                        y: isHovered ? 0 : 2
                    )
                Image(systemName: glyphStyle.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [glyphStyle.highlightColor, glyphStyle.color],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: glyphStyle.color.opacity(isHovered ? 0.72 : 0.24),
                        radius: isHovered ? 6 : 2
                    )
                    .scaleEffect(isHovered ? 1.08 : 1)
                    .animation(
                        HUDMetrics.motion(.spring(response: 0.24, dampingFraction: 0.72)),
                        value: isHovered
                    )
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if isEditingTitle {
                        InlineTitleTextField(
                            text: Binding(
                                get: { model.titleDraft },
                                set: { model.titleDraft = $0 }
                            ),
                            placeholder: "例如：日志查询",
                            onSubmit: {
                                finishTitleEditing(save: true)
                            },
                            onCancel: {
                                finishTitleEditing(save: false)
                            }
                        )
                        .frame(height: 25)

                        RowTitleActionButton(
                            symbol: "checkmark",
                            tint: AgentStatus.completed.color,
                            help: "保存标题备注"
                        ) {
                            finishTitleEditing(save: true)
                        }

                        RowTitleActionButton(symbol: "xmark", help: "取消编辑") {
                            finishTitleEditing(save: false)
                        }
                    } else {
                        Text(model.privacyMode ? "任务标题已隐藏" : model.displayTitle(for: session))
                            .font(HUDMetrics.Typography.title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !model.privacyMode, isHovered {
                            Button {
                                beginTitleEditing()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(HUDTheme.textSecondary)
                                    .frame(width: 18, height: 18)
                                    .background(
                                        HUDTheme.controlFill,
                                        in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("编辑标题备注")
                            .accessibilityLabel("编辑标题备注")
                            .transition(.opacity.combined(with: .scale(scale: 0.82)))
                        }
                    }

                    Spacer(minLength: 4)

                    if isHovered, !model.privacyMode {
                        Button {
                            model.suppressNextRowOpen(for: session)
                            withAnimation(HUDMetrics.listAnimation) {
                                model.dismiss(session)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(HUDTheme.textSecondary)
                                .frame(width: 21, height: 21)
                                .background(
                                    HUDTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("从列表删除，有新动态时自动回来")
                        .accessibilityLabel("从列表删除，有新动态时自动回来")
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                    }

                    Button {
                        model.suppressNextRowOpen(for: session)
                        if !isImportant, !HUDMetrics.reduceMotion {
                            motion.playImportantBurst()
                        } else {
                            motion.cancelImportantBurst()
                        }
                        withAnimation(HUDMetrics.listAnimation) {
                            model.toggleImportance(for: session)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(importantTint, lineWidth: 1.5)
                                .scaleEffect(motion.importantBurst ? 0.68 : 1.85)
                                .opacity(motion.importantBurst ? 1 : 0)

                            RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                                .fill(
                                    isImportant
                                        ? importantTint.opacity(motion.importantBurst ? 0.34 : 0.20)
                                        : HUDTheme.controlFill
                                )

                            Image(systemName: isImportant ? "star.fill" : "star")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(isImportant ? importantTint : HUDTheme.textSecondary)
                                .symbolEffect(.bounce, value: isImportant)
                                .shadow(
                                    color: importantTint.opacity(isImportant ? 0.60 : 0),
                                    radius: motion.importantBurst ? 8 : 3
                                )
                        }
                        .frame(width: 24, height: 24)
                        .overlay {
                            if isImportant {
                                RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                                    .strokeBorder(importantTint.opacity(0.38), lineWidth: 0.7)
                            }
                        }
                        .shadow(
                            color: importantTint.opacity(isImportant ? 0.30 : 0),
                            radius: motion.importantBurst ? 10 : 5
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isImportant ? "取消重要" : "标记为重要并置顶")
                    .accessibilityLabel(isImportant ? "取消重要" : "标记为重要并置顶")

                    StatusBadge(status: session.status, confidence: session.confidence)
                }

                HStack(spacing: 5) {
                    Text(session.provider.shortName)
                        .font(HUDMetrics.Typography.agent)
                        .foregroundStyle(glyphStyle.color)
                    Text("·")
                    Text(model.privacyMode ? "项目已隐藏" : session.projectName)
                    if let git = session.git {
                        Text("·")
                        Text("\(git.changedFiles) 个改动")
                    }
                }
                .font(HUDMetrics.Typography.caption)
                .foregroundStyle(HUDTheme.textSecondary)
                .lineLimit(1)

                HStack(spacing: 5) {
                    StatusDot(
                        color: session.status.color,
                        animates: model.advancedAnimations
                            && session.status.isRunning
                            && !HUDMetrics.reduceMotion
                    )
                    Text(model.privacyMode ? "当前动作已隐藏" : session.currentAction)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 5)
                    Text(session.lastActivityAt.relativeShort)
                        .monospacedDigit()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(HUDTheme.textSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .padding(.top, 12)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .background {
            SessionRowSurface(
                status: session.status,
                isHovered: isHovered,
                accent: rowAccent,
                isImportant: isImportant,
                hoverLocation: motion.hoverLocation,
                animatesImportant: model.advancedAnimations
            )
        }
        .overlay(alignment: .leading) {
            if showsEdgeLight {
                Capsule()
                    .fill(rowAccent)
                    .frame(width: 3)
                    .padding(.vertical, 18)
                    .padding(.leading, 8)
                    .shadow(
                        color: rowAccent.opacity(isHovered ? 0.82 : (isImportant ? 0.52 : 0.36)),
                        radius: isHovered ? 8 : 4
                    )
            }
        }
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        rowAccent.opacity(0.82),
                        lineWidth: 1.2
                    )
                    .padding(.horizontal, 8)
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: isHovered
                ? rowAccent.opacity(0.38)
                : (isImportant ? importantTint.opacity(0.15) : HUDTheme.Shadow.rowBase.color),
            radius: isHovered ? 13 : (isImportant ? 8 : HUDTheme.Shadow.rowBase.radius),
            y: isHovered ? 0 : HUDTheme.Shadow.rowBase.y
        )
        .animation(HUDMetrics.motion(.easeOut(duration: 0.18)), value: isHovered)
        .opacity(isDeparting ? 0 : (isArriving && !arrivalVisible ? 0 : 1))
        .offset(
            x: 0,
            y: isArriving && !arrivalVisible ? 8 : 0
        )
        .zIndex(isDeparting ? 1 : 0)
        .animation(
            .timingCurve(
                0.4,
                0,
                0.8,
                0.35,
                duration: SessionCompletionAnimation.exitDuration
            ),
            value: isDeparting
        )
        .animation(
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.28),
            value: arrivalVisible
        )
        .onTapGesture {
            if model.consumeRowOpenSuppression(for: session) {
                return
            }
            guard !isEditingTitle else {
                return
            }
            onOpen()
        }
        .onHover { hovered in
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.16)) {
                model.setHoveredSession(session.id, hovered: hovered)
            }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                motion.hoverLocation = location
            case .ended:
                motion.hoverLocation = nil
            }
        }
        .onDisappear {
            if isHovered {
                model.setHoveredSession(session.id, hovered: false)
            }
        }
        .allowsHitTesting(!isDeparting && !isArriving)
        .accessibilityHidden(isDeparting || isArriving)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "打开详情") {
            onOpen()
        }
    }

    private func beginTitleEditing() {
        model.suppressNextRowOpen(for: session)
        model.beginTitleEditing(for: session)
    }

    private func finishTitleEditing(save: Bool) {
        model.suppressNextRowOpen(for: session)
        if save {
            model.saveTitleEditing(for: session)
        } else {
            model.cancelTitleEditing()
        }
    }
}

private let importantTint = HUDTheme.important

/// 会话行的渐变背景与悬停霓虹；重要描边只呼吸发光，不缩放卡片。
/// 独立成视图便于离屏渲染做像素级验证。
struct SessionRowSurface: View {
    let status: AgentStatus
    let isHovered: Bool
    let accent: Color
    let isImportant: Bool
    let hoverLocation: CGPoint?
    let animatesImportant: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: HUDTheme.cardGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: HUDTheme.cardBorderGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }

                if SessionRowSurfacePolicy.isStatusTinted(status) {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    status.color.opacity(isHovered ? 0.055 : 0.028),
                                    status.color.opacity(isHovered ? 0.025 : 0.010)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                if isImportant {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    importantTint.opacity(colorScheme == .dark ? 0.12 : 0.075),
                                    importantTint.opacity(0.018)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                if isHovered, let hoverLocation {
                    RadialGradient(
                        colors: [
                            accent.opacity(colorScheme == .dark ? 0.36 : 0.20),
                            accent.opacity(colorScheme == .dark ? 0.12 : 0.06),
                            Color.clear
                        ],
                        center: UnitPoint(
                            x: min(max(hoverLocation.x / max(proxy.size.width, 1), 0), 1),
                            y: min(max(hoverLocation.y / max(proxy.size.height, 1), 0), 1)
                        ),
                        startRadius: 4,
                        endRadius: 115
                    )
                    .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous))
                    .blendMode(colorScheme == .dark ? .screen : .normal)
                    .transition(.opacity)
                }

                if isImportant {
                    ImportantBorder(
                        isHovered: isHovered,
                        animates: animatesImportant && !HUDMetrics.reduceMotion
                    )
                } else if isHovered {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .strokeBorder(accent.opacity(0.58), lineWidth: 1.2)
                        .shadow(color: accent.opacity(0.46), radius: 10)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct ImportantBorder: View {
    let isHovered: Bool
    let animates: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
            .strokeBorder(importantTint.opacity(isHovered ? 0.56 : 0.24), lineWidth: 0.9)
            .overlay {
                if animates {
                    OpacityPulseLayer(
                        color: importantTint.opacity(0.68),
                        cornerRadius: HUDMetrics.Radius.card,
                        lineWidth: 1.2,
                        shadowRadius: 13,
                        minimumOpacity: 0.14,
                        duration: 1.7
                    )
                    .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .strokeBorder(importantTint.opacity(0.28), lineWidth: 1)
                }
            }
    }
}

/// A repeating opacity animation that stays on Core Animation's render thread.
/// SwiftUI symbol effects and phase animators otherwise rebuild the HUD view tree.
private struct OpacityPulseLayer: NSViewRepresentable {
    let color: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let shadowRadius: CGFloat
    let minimumOpacity: Double
    let duration: Double

    func makeNSView(context: Context) -> OpacityPulseNSView {
        OpacityPulseNSView()
    }

    func updateNSView(_ view: OpacityPulseNSView, context: Context) {
        view.configure(
            color: NSColor(color).cgColor,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            shadowRadius: shadowRadius,
            minimumOpacity: minimumOpacity,
            duration: duration
        )
    }
}

private final class OpacityPulseNSView: NSView {
    private let pulseLayer = CAShapeLayer()
    private var cornerRadius: CGFloat = 0
    private var lineWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(pulseLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulseLayer.frame = bounds
        let pathBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = lineWidth == 0
            ? CGPath(ellipseIn: pathBounds, transform: nil)
            : CGPath(
                roundedRect: pathBounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        pulseLayer.path = path
        pulseLayer.shadowPath = path
        CATransaction.commit()
    }

    func configure(
        color: CGColor,
        cornerRadius: CGFloat,
        lineWidth: CGFloat,
        shadowRadius: CGFloat,
        minimumOpacity: Double,
        duration: Double
    ) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulseLayer.fillColor = lineWidth == 0 ? color : CGColor.clear
        pulseLayer.strokeColor = lineWidth == 0 ? nil : color
        pulseLayer.lineWidth = lineWidth
        pulseLayer.shadowColor = color
        pulseLayer.shadowOpacity = shadowRadius == 0 ? 0 : 0.68
        pulseLayer.shadowRadius = shadowRadius
        pulseLayer.shadowOffset = .zero
        CATransaction.commit()
        needsLayout = true

        guard pulseLayer.animation(forKey: "hud.opacity") == nil else {
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = minimumOpacity
        animation.toValue = 1
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseLayer.add(animation, forKey: "hud.opacity")
    }
}

private struct StatusDot: View {
    let color: Color
    let animates: Bool

    var body: some View {
        // 脉冲（高级动画）是逐行常驻动画，会话越多开销越大，
        // 因此默认关闭、由用户在设置里按需开启；关闭时保持静态实心点。
        Group {
            if animates {
                OpacityPulseLayer(
                    color: color,
                    cornerRadius: 2.5,
                    lineWidth: 0,
                    shadowRadius: 0,
                    minimumOpacity: 0.38,
                    duration: 1.15
                )
            } else {
                Circle()
                    .fill(color)
            }
        }
        .frame(width: 5, height: 5)
        .allowsHitTesting(false)
    }
}

private struct RowTitleActionButton: View {
    let symbol: String
    var tint: Color = HUDTheme.textSecondary
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(
                    HUDTheme.controlFill,
                    in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct InlineTitleTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12.5, weight: .semibold)
        field.textColor = .labelColor
        field.backgroundColor = .textBackgroundColor.withAlphaComponent(0.82)
        field.drawsBackground = true
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.wantsLayer = true
        field.layer?.cornerRadius = HUDMetrics.Radius.control
        field.layer?.borderWidth = 0.8
        field.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor

        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTitleTextField

        init(parent: InlineTitleTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

private struct TaskRunView: View {
    let run: TaskRun
    let privacyMode: Bool
    let projectPath: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                Circle()
                    .fill(AgentStatus.completed.color)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                Rectangle()
                    .fill(HUDTheme.divider)
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(run.completedAt.formatted(.dateTime.month().day().hour().minute()))
                        .font(HUDMetrics.Typography.caption)
                        .foregroundStyle(HUDTheme.textSecondary)
                    Spacer()
                    Text("本地摘要")
                        .font(HUDMetrics.Typography.micro)
                        .foregroundStyle(HUDTheme.textTertiary)
                }

                Text(privacyMode ? "任务目标已隐藏" : run.objective)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)

                Text(privacyMode ? "完成总结已隐藏" : run.summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(7)

                if !privacyMode, !run.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("执行过程")
                            .font(HUDMetrics.Typography.micro)
                            .foregroundStyle(HUDTheme.textTertiary)
                        ForEach(Array(run.actions.prefix(6)), id: \.self) { action in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(HUDTheme.textTertiary)
                                    .padding(.top, 2)
                                Text(action)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(HUDTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                if !privacyMode, !run.filesChanged.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("涉及文件")
                            .font(HUDMetrics.Typography.micro)
                            .foregroundStyle(HUDTheme.textTertiary)
                        ForEach(Array(run.filesChanged.prefix(5)), id: \.self) { path in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 9))
                                Text(relativeFile(path, projectPath: projectPath))
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(HUDTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PromptImageGallery: View {
    let images: [SessionImageAttachment]

    private let columns = [
        GridItem(.adaptive(minimum: 78), spacing: 7, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                Button {
                    ImagePreviewWindowController.shared.show(
                        images: images,
                        initialIndex: index
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(SessionImageAttachment.displayLabel(for: index))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(HUDTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 27)
                    .background(
                        HUDTheme.controlFill,
                        in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                            .strokeBorder(HUDTheme.border, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .help("查看图片 \(index + 1)")
                .accessibilityLabel("查看\(SessionImageAttachment.displayLabel(for: index))")
            }
        }
    }
}

private struct SessionAttachmentImage: View {
    let attachment: SessionImageAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SessionAttachmentImageView(source: attachment.source)
            .frame(width: 214, height: 132)
            .background(HUDTheme.controlFill)
            .clipShape(RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                    .strokeBorder(HUDTheme.border, lineWidth: 0.8)
            }

            if let label = attachment.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 214, alignment: .leading)
            }
        }
    }
}

private struct SessionAttachmentImageView: NSViewRepresentable {
    let source: SessionImageSource

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        updateImage(imageView)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        updateImage(nsView)
    }

    private func updateImage(_ imageView: NSImageView) {
        if let image = SessionImageCache.image(for: source) {
            imageView.image = image
            imageView.contentTintColor = nil
            return
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .light)
        imageView.image = NSImage(
            systemSymbolName: "photo.badge.exclamationmark",
            accessibilityDescription: "图片不可读取"
        )?.withSymbolConfiguration(configuration)
        imageView.contentTintColor = .tertiaryLabelColor
    }
}

enum SessionImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for source: SessionImageSource) -> NSImage? {
        let key = cacheKey(for: source)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: NSImage?
        switch source {
        case .localPath(let path):
            image = NSImage(contentsOfFile: path)
        case .dataURL(let value):
            guard let comma = value.firstIndex(of: ",") else {
                return nil
            }
            let payload = String(value[value.index(after: comma)...])
            image = Data(base64Encoded: payload).flatMap(NSImage.init(data:))
        case .unavailable:
            image = nil
        }

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private static func cacheKey(for source: SessionImageSource) -> NSString {
        switch source {
        case .localPath(let path):
            return "local:\(path)" as NSString
        case .dataURL(let value):
            return "data:\(value.hashValue):\(value.count)" as NSString
        case .unavailable:
            return "unavailable" as NSString
        }
    }
}

private struct ImportantCompletionCallout: View {
    let notice: ImportantCompletionNotice
    let privacyMode: Bool
    let onReveal: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    CalloutCaret()
                        .fill(AgentStatus.completed.color)
                        .frame(width: 15, height: 7)
                        .shadow(
                            color: AgentStatus.completed.color.opacity(0.55),
                            radius: 4
                        )

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AgentStatus.completed.color.opacity(0.82),
                                    AgentStatus.completed.color.opacity(0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1.5, height: 38)
                }
                .padding(.leading, 31)

                Spacer()
            }
            .allowsHitTesting(false)

            HStack(spacing: 7) {
                Button(action: onReveal) {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                                .fill(notice.provider.accentColor.opacity(0.18))
                            Image(systemName: notice.provider.symbolName)
                                .font(HUDMetrics.Typography.label)
                                .foregroundStyle(notice.provider.accentColor)
                        }
                        .frame(width: 29, height: 29)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(notice.provider.shortName)
                                    .font(HUDMetrics.Typography.agent)
                                    .foregroundStyle(notice.provider.accentColor)

                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(importantTint)

                                Text(
                                    privacyMode
                                        ? "重要会话标题已隐藏"
                                        : notice.title
                                )
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(HUDTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            }

                            HStack(spacing: 5) {
                                Text("进行中")
                                    .foregroundStyle(AgentStatus.working.color)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(HUDTheme.textTertiary)
                                Text("已完成")
                                    .foregroundStyle(AgentStatus.completed.color)

                                Spacer(minLength: 5)

                                Text("查看全部")
                                    .foregroundStyle(HUDTheme.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(HUDTheme.textTertiary)
                            }
                            .font(HUDMetrics.Typography.micro)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("切回全部筛选并查看 \(notice.title)")
                .accessibilityLabel("重要会话从进行中变为已完成，点击查看全部")

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .background(
                            HUDTheme.controlFill,
                            in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.micro, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help("关闭重要会话提醒")
                .accessibilityLabel("关闭重要会话提醒")
            }
            .padding(.leading, 10)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .fill(HUDTheme.surfaceRaised)
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    importantTint.opacity(0.17),
                                    AgentStatus.completed.color.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                importantTint.opacity(0.78),
                                AgentStatus.completed.color.opacity(0.72)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: Color.black.opacity(0.2),
                radius: 14,
                y: 6
            )
            .shadow(
                color: AgentStatus.completed.color.opacity(0.24),
                radius: 9
            )
            .padding(.horizontal, 9)
        }
    }
}

private struct CalloutCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

@MainActor
private final class FilterHoverState: ObservableObject {
    @Published var status: StatusFilter?
    @Published var provider: ProviderFilter?
}

private struct OverviewStrip: View {
    let selectedFilter: StatusFilter
    let highlightAll: Bool
    let count: (StatusFilter) -> Int
    let onSelect: (StatusFilter) -> Void
    @Namespace private var selectionNamespace
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var hover = FilterHoverState()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatusFilter.allCases) { filter in
                let selected = filter == selectedFilter
                let hovered = hover.status == filter

                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 5) {
                        Text(filter.label)
                            .font(.system(size: 11.5, weight: .semibold))

                        Text("\(count(filter))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .frame(minWidth: 17, minHeight: 17)
                            .background(
                                selected ? filter.color.opacity(0.12) : HUDTheme.controlFill,
                                in: Capsule()
                            )
                    }
                    .foregroundStyle(
                        selected
                            ? HUDTheme.selectionText
                            : (hovered ? filter.color : HUDTheme.textSecondary)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 33)
                    .background {
                        if selected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: HUDTheme.selectionGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            filter.color.opacity(colorScheme == .dark ? 0.82 : 0.46),
                                            lineWidth: 0.9
                                        )
                                }
                                .matchedGeometryEffect(
                                    id: "overview-selection",
                                    in: selectionNamespace
                                )
                        } else if hovered {
                            Capsule()
                                .fill(filter.color.opacity(colorScheme == .dark ? 0.13 : 0.09))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(filter.color.opacity(0.36), lineWidth: 0.7)
                                }
                        }
                    }
                    .shadow(
                        color: filter.color.opacity(
                            selected ? (colorScheme == .dark ? 0.64 : 0.30) : (hovered ? 0.28 : 0)
                        ),
                        radius: selected ? (colorScheme == .dark ? 12 : 8) : (hovered ? 7 : 0),
                        y: 0
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hover.status = isHovered ? filter : nil
                }
                .overlay {
                    if filter == .all, highlightAll {
                        Capsule()
                            .strokeBorder(
                                AgentStatus.completed.color.opacity(0.88),
                                lineWidth: 1.2
                            )
                            .shadow(
                                color: AgentStatus.completed.color.opacity(0.58),
                                radius: 6
                            )
                            .allowsHitTesting(false)
                    }
                }
                .help("显示\(filter.label)的 Agent 会话")
                .accessibilityLabel("\(filter.label)，\(count(filter)) 个会话")
            }
        }
        .padding(3)
        .background(
            LinearGradient(
                colors: HUDTheme.filterBarGradient,
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? HUDTheme.border : Color.white.opacity(0.58),
                    lineWidth: 0.7
                )
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(height: 46)
        .animation(HUDMetrics.motion(HUDMetrics.filterAnimation), value: selectedFilter)
        .animation(HUDMetrics.motion(.easeOut(duration: 0.15)), value: hover.status)
    }
}

private struct ProviderFilterStrip: View {
    let selectedFilter: ProviderFilter
    let highlightAll: Bool
    let count: (ProviderFilter) -> Int
    let onSelect: (ProviderFilter) -> Void
    @Namespace private var selectionNamespace
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var hover = FilterHoverState()

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProviderFilter.allCases) { filter in
                let selected = filter == selectedFilter
                let hovered = hover.provider == filter

                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.symbolName)
                            .font(.system(size: 9.5, weight: .semibold))

                        Text(filter.label)
                            .font(.system(size: 11, weight: .medium))

                        Text("\(count(filter))")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .opacity(selected ? 0.9 : 0.65)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(
                        selected
                            ? HUDTheme.selectionText
                            : (filter == .all ? HUDTheme.textSecondary : filter.accentColor)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 29)
                    .background {
                        if selected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: HUDTheme.selectionGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .matchedGeometryEffect(
                                    id: "provider-selection",
                                    in: selectionNamespace
                                )
                        } else {
                            Capsule()
                                .fill(filter.accentColor.opacity(hovered ? 0.14 : 0.055))
                                .background(
                                    LinearGradient(
                                        colors: HUDTheme.filterPillGradient,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    in: Capsule()
                                )
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                selected
                                    ? filter.accentColor.opacity(0.72)
                                    : filter.accentColor.opacity(hovered ? 0.58 : 0.16),
                                lineWidth: hovered || selected ? 0.9 : 0.7
                            )
                    }
                    .shadow(
                        color: filter.accentColor.opacity(
                            selected ? (colorScheme == .dark ? 0.52 : 0.24) : (hovered ? 0.32 : 0)
                        ),
                        radius: selected ? (colorScheme == .dark ? 11 : 7) : (hovered ? 8 : 0),
                        y: 0
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hover.provider = isHovered ? filter : nil
                }
                .overlay {
                    if filter == .all, highlightAll {
                        Capsule()
                            .strokeBorder(
                                AgentStatus.completed.color.opacity(0.82),
                                lineWidth: 1.1
                            )
                            .shadow(
                                color: AgentStatus.completed.color.opacity(0.48),
                                radius: 5
                            )
                            .allowsHitTesting(false)
                    }
                }
                .help("只显示 \(filter.label) 会话")
                .accessibilityLabel("\(filter.label)，\(count(filter)) 个会话")
                    }
                }
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(height: 44)
        .background(
            LinearGradient(
                colors: HUDTheme.filterBarGradient,
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
        )
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                    .strokeBorder(HUDTheme.border, lineWidth: 0.7)
            }
        }
        .padding(.horizontal, 12)
        .animation(HUDMetrics.motion(HUDMetrics.filterAnimation), value: selectedFilter)
        .animation(HUDMetrics.motion(.easeOut(duration: 0.15)), value: hover.provider)
    }
}

private struct CompactMetric: View {
    let symbol: String
    let color: Color
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}

private struct StatusBadge: View {
    let status: AgentStatus
    let confidence: StatusConfidence

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.shortLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            LinearGradient(
                colors: [
                    status.color.opacity(0.17),
                    status.color.opacity(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(status.color.opacity(0.22), lineWidth: 0.8)
        }
        .help("\(status.label) · \(confidence.label)")
    }
}

private struct PrivacyStrip: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 10))
            Text("隐私模式已开启，标题、路径、原始输入、图片和总结均已隐藏")
                .font(HUDMetrics.Typography.caption)
            Spacer()
        }
        .foregroundStyle(AgentStatus.waitingUser.color)
        .padding(.horizontal, 14)
        .frame(height: 29)
        .background(AgentStatus.waitingUser.color.opacity(0.08))
    }
}

private struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HUDTheme.textSecondary)
            Text(title)
                .font(HUDMetrics.Typography.label)
        }
    }
}

private struct DetailFact: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5))
            Text(text)
                .lineLimit(1)
        }
        .font(HUDMetrics.Typography.caption)
        .foregroundStyle(HUDTheme.textSecondary)
    }
}

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取本地会话")
                .font(.system(size: 11.5))
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyState: View {
    let statusFilter: StatusFilter
    let providerFilter: ProviderFilter

    private var title: String {
        if providerFilter != .all, statusFilter == .all {
            return "\(providerFilter.label) 暂无会话"
        }
        if statusFilter == .working {
            return "当前没有运行中的 Agent"
        }
        return "没有符合条件的会话"
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(HUDTheme.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text("AgentHUD 正在只读监听 Codex、Claude、Pi 与 OpenCode")
                .font(.system(size: 11.5))
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 30)
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: HUDTheme.brandGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous)
                .strokeBorder(HUDTheme.accent.opacity(0.35), lineWidth: 0.9)
            Image(systemName: "rectangle.3.group")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(HUDTheme.textPrimary)
        }
        .frame(width: size, height: size)
        .shadow(color: HUDTheme.rowShadow, radius: 4, y: 2)
    }
}

private struct BrandToggleButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BrandMark(size: isExpanded ? 42 : 28)
                .contentShape(RoundedRectangle(cornerRadius: HUDMetrics.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "收起 AgentHUD" : "展开 AgentHUD")
        .accessibilityLabel(isExpanded ? "收起 AgentHUD" : "展开 AgentHUD")
    }
}

private struct HUDDragHandle: View {
    let positionLocked: Bool

    var body: some View {
        ZStack {
            WindowDragHandle(isEnabled: !positionLocked)

            Image(systemName: positionLocked ? "pin.fill" : "line.3.horizontal")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(
                    positionLocked
                        ? AgentStatus.waitingUser.color
                        : HUDTheme.textSecondary
                )
                .allowsHitTesting(false)
        }
        .frame(width: 18, height: 30)
        .help(positionLocked ? "位置已锁定" : "拖动 AgentHUD")
        .accessibilityLabel(positionLocked ? "位置已锁定" : "拖动 AgentHUD")
    }
}

private struct HUDIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = HUDTheme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 29, height: 29)
                .background(
                    HUDTheme.toolbarIdle,
                    in: RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous)
                        .strokeBorder(HUDTheme.border.opacity(0.55), lineWidth: 0.6)
                }
                .contentShape(RoundedRectangle(cornerRadius: HUDMetrics.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private func relativeFile(_ path: String, projectPath: String) -> String {
    let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
    if path.hasPrefix(prefix) {
        return String(path.dropFirst(prefix.count))
    }
    return URL(fileURLWithPath: path).lastPathComponent
}

private func abbreviatedPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}


private struct StarlightBackground: View {
    let opacity: Double

    private static let stars: [Star] = {
        var result: [Star] = []
        var state: UInt64 = 0xC0FFEE1234ABCDEF
        func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = (state >> 11) & 0x1F_FFFF_FFFF_FFFF
            return Double(value) / Double(0x1F_FFFF_FFFF_FFFF)
        }
        for index in 0..<96 {
            let x = nextUnit()
            let y = nextUnit()
            let radius = 0.45 + nextUnit() * 1.55
            let base = 0.18 + nextUnit() * 0.72
            let phase = Double(index) * 0.73 + nextUnit() * .pi
            result.append(Star(x: x, y: y, radius: radius, baseOpacity: base, phase: phase))
        }
        return result
    }()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.18).opacity(opacity),
                    Color(red: 0.10, green: 0.08, blue: 0.24).opacity(opacity),
                    Color(red: 0.03, green: 0.04, blue: 0.12).opacity(opacity)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.34, green: 0.30, blue: 0.78).opacity(0.28 * opacity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.18, y: 0.12),
                startRadius: 10,
                endRadius: 320
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.45, blue: 0.80).opacity(0.22 * opacity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.88, y: 0.18),
                startRadius: 10,
                endRadius: 280
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            RadialGradient(
                colors: [
                    Color(red: 0.62, green: 0.28, blue: 0.72).opacity(0.16 * opacity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.72, y: 0.82),
                startRadius: 20,
                endRadius: 360
            )
            .blendMode(.screen)
            .allowsHitTesting(false)

            if HUDMetrics.reduceMotion {
                starCanvas(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    starCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func starCanvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            for star in Self.stars {
                let twinkle = HUDMetrics.reduceMotion
                    ? 1.0
                    : 0.72 + 0.28 * sin(time * 1.15 + star.phase)
                let alpha = min(1.0, star.baseOpacity * twinkle * (0.55 + 0.45 * opacity))
                let rect = CGRect(
                    x: star.x * size.width - star.radius,
                    y: star.y * size.height - star.radius,
                    width: star.radius * 2,
                    height: star.radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
            }
        }
        .blur(radius: 0.15)
        .allowsHitTesting(false)
    }

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let baseOpacity: Double
        let phase: Double
    }
}
