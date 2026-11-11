import AppKit
import Combine
import SwiftUI

struct HUDShell: View {
    @ObservedObject var model: HUDViewModel
    @ObservedObject private var runPagination = SessionRunPagination()
    @Environment(\.colorScheme) private var colorScheme

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
                    width: HUDMetrics.expandedWidth,
                    height: HUDMetrics.expandedHeight,
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
                .animation(HUDMetrics.pageAnimation, value: model.selectedSessionID)

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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        }
        .preferredColorScheme(nil)
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 4)),
            removal: .opacity.combined(with: .offset(x: -3))
        )
    }

    private var background: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            HUDTheme.windowTint
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.045), Color.clear]
                    : [Color.white.opacity(0.3), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

            HUDIconButton(symbol: "gearshape", help: "AI 标题设置") {
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
        VStack(spacing: 0) {
            expandedHeader

            if model.privacyMode {
                PrivacyStrip()
            }

            filterSurface
                .zIndex(model.shouldShowImportantCompletionNotice ? 10 : 0)

            Group {
                if model.isLoading && model.sessions.isEmpty {
                    LoadingState()
                } else if model.visibleSessionRows.isEmpty {
                    EmptyState(
                        statusFilter: model.statusFilter,
                        providerFilter: model.providerFilter
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.visibleSessionRows) { row in
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
                                Divider()
                                    .padding(.leading, 58)
                                    .opacity(0.45)
                            }
                        }
                        .animation(
                            HUDMetrics.listAnimation,
                            value: model.visibleSessionRows.map(\.id)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                BrandToggleButton(isExpanded: true) {
                    model.collapse()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AGENT HUD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(model.activeCount > 0 ? "\(model.activeCount) 个 Agent 正在进行" : "本地只读监视中")
                        .font(.system(size: 11))
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
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
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
                visibleCount: model.visibleSessions.count,
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
                .frame(width: HUDMetrics.expandedWidth - 18, alignment: .leading)
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
        .background(HUDTheme.surface.opacity(0.42))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
            Text("只读")
            Spacer()
            if let scannedAt = model.lastScannedAt {
                Text("更新于 \(scannedAt.clockTime)")
                    .monospacedDigit()
            } else {
                Text("正在读取")
            }
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
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
        .background {
            WindowDragHandle(isEnabled: !model.positionLocked)
        }
        .help(model.positionLocked ? "位置已锁定" : "拖动任意表头区域移动")
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.privacyMode {
                Text("任务标题已隐藏")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(2)
            } else if model.editingTitleSessionID == session.id {
                titleEditor
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.displayTitle(for: session))
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Spacer(minLength: 8)

                    if model.hoveredSessionID == session.id {
                        Button {
                            model.beginTitleEditing(for: session)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HUDTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    HUDTheme.controlFill,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                    .font(.system(size: 9.5, weight: .semibold))

                    Text(model.titleSource(for: session).label)
                        .font(.system(size: 10, weight: .medium))

                    if model.hasCustomTitle(for: session) {
                        Text("·")
                        Button("恢复自动标题") {
                            model.clearCustomTitle(for: session)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
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
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                            .font(.system(size: 9.5, weight: .semibold))
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
                        .font(.system(size: 9, weight: .semibold))
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
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                                .font(.system(size: 9, weight: .semibold))
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

private struct AgentRowView: View {
    @ObservedObject var model: HUDViewModel
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

    private var isCompleted: Bool {
        session.status == .completed
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(session.provider.accentColor.opacity(0.12))
                Image(systemName: session.provider.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.provider.accentColor)
            }
            .frame(width: 33, height: 33)

            VStack(alignment: .leading, spacing: 5) {
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
                            .font(.system(size: 13, weight: .semibold))
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
                                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("编辑标题备注")
                            .accessibilityLabel("编辑标题备注")
                            .transition(.opacity.combined(with: .scale(scale: 0.82)))
                        }
                    }

                    Spacer(minLength: 4)

                    Button {
                        model.suppressNextRowOpen(for: session)
                        withAnimation(HUDMetrics.filterAnimation) {
                            model.toggleImportance(for: session)
                        }
                    } label: {
                        Image(systemName: isImportant ? "star.fill" : "star")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isImportant ? importantTint : HUDTheme.textSecondary)
                            .frame(width: 21, height: 21)
                            .background(
                                isImportant
                                    ? importantTint.opacity(0.13)
                                    : HUDTheme.controlFill,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isImportant ? "取消重要" : "标记为重要并置顶")
                    .accessibilityLabel(isImportant ? "取消重要" : "标记为重要并置顶")

                    StatusBadge(status: session.status, confidence: session.confidence)
                }

                HStack(spacing: 5) {
                    Text(session.provider.shortName)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    Text("·")
                    Text(model.privacyMode ? "项目已隐藏" : session.projectName)
                    if let git = session.git {
                        Text("·")
                        Text("\(git.changedFiles) 个改动")
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
                .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 5, height: 5)
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
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .padding(.top, 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background {
            ZStack {
                HUDTheme.surface.opacity(isHovered ? 0.72 : 0.34)
                if isCompleted {
                    AgentStatus.completed.color.opacity(isHovered ? 0.07 : 0.04)
                }
            }
        }
        .overlay {
            if isCompleted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        AgentStatus.completed.color.opacity(isHovered ? 0.86 : 0.64),
                        lineWidth: isHovered ? 1.3 : 1
                    )
                    .shadow(
                        color: AgentStatus.completed.color.opacity(isHovered ? 0.52 : 0.34),
                        radius: isHovered ? 10 : 7
                    )
                    .shadow(
                        color: AgentStatus.completed.color.opacity(0.22),
                        radius: 2
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
        }
        .opacity(isDeparting ? 0 : (isArriving && !arrivalVisible ? 0 : 1))
        .offset(
            x: isDeparting ? 118 : 0,
            y: isArriving && !arrivalVisible ? 12 : 0
        )
        .scaleEffect(
            isArriving && !arrivalVisible ? 0.985 : 1,
            anchor: .top
        )
        .blur(radius: isDeparting ? 1.8 : 0)
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
            .spring(response: 0.36, dampingFraction: 0.88),
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
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
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
        field.layer?.cornerRadius = 5
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
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(HUDTheme.textSecondary)
                    Spacer()
                    Text("本地摘要")
                        .font(.system(size: 9, weight: .semibold))
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
                            .font(.system(size: 9.5, weight: .semibold))
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
                            .font(.system(size: 9.5, weight: .semibold))
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
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(notice.provider.accentColor.opacity(0.18))
                            Image(systemName: notice.provider.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(notice.provider.accentColor)
                        }
                        .frame(width: 29, height: 29)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(notice.provider.shortName)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
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
                            .font(.system(size: 9.5, weight: .semibold))
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
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(HUDTheme.surfaceRaised)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

private struct OverviewStrip: View {
    let selectedFilter: StatusFilter
    let highlightAll: Bool
    let count: (StatusFilter) -> Int
    let onSelect: (StatusFilter) -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatusFilter.allCases) { filter in
                let selected = filter == selectedFilter

                Button {
                    onSelect(filter)
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(filter.label)
                                .font(.system(size: 10.5, weight: .semibold))

                            Text("\(count(filter))")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 14)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            filter.color.opacity(selected ? 0.24 : 0.11),
                                            filter.color.opacity(selected ? 0.10 : 0.045)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            filter.color.opacity(selected ? 0.52 : 0.18),
                                            lineWidth: 0.8
                                        )
                                }
                        }
                        .foregroundStyle(selected ? filter.color : HUDTheme.textSecondary)

                        Capsule()
                            .fill(
                                selected
                                    ? LinearGradient(
                                        colors: [
                                            filter.color.opacity(0.72),
                                            filter.color
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.clear, Color.clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .frame(width: 22, height: 2)
                            .shadow(
                                color: selected ? filter.color.opacity(0.58) : .clear,
                                radius: 4
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            filter.color.opacity(0.24),
                                            filter.color.opacity(0.09)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    HUDTheme.borderStrong,
                                                    filter.color.opacity(0.58)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 0.9
                                        )
                                }
                                .matchedGeometryEffect(
                                    id: "overview-selection",
                                    in: selectionNamespace
                                )
                        }
                    }
                    .shadow(
                        color: selected ? filter.color.opacity(0.24) : .clear,
                        radius: selected ? 6 : 0,
                        y: 2
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay {
                    if filter == .all, highlightAll {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
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
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(height: 45)
        .background(HUDTheme.surface.opacity(0.42))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HUDTheme.divider)
                .frame(height: 0.5)
        }
        .animation(HUDMetrics.filterAnimation, value: selectedFilter)
    }
}

private struct ProviderFilterStrip: View {
    let selectedFilter: ProviderFilter
    let highlightAll: Bool
    let count: (ProviderFilter) -> Int
    let visibleCount: Int
    let onSelect: (ProviderFilter) -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProviderFilter.allCases) { filter in
                let selected = filter == selectedFilter

                Button {
                    onSelect(filter)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.symbolName)
                            .font(.system(size: 8.5, weight: .semibold))

                        Text(filter.label)
                            .font(.system(size: 10.5, weight: .semibold))

                        Text("\(count(filter))")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .opacity(selected ? 0.9 : 0.65)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(selected ? filter.accentColor : HUDTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background {
                        if selected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            filter.accentColor.opacity(0.28),
                                            filter.accentColor.opacity(0.1)
                                        ],
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
                                .fill(HUDTheme.controlFill)
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                selected
                                    ? LinearGradient(
                                        colors: [
                                            HUDTheme.borderStrong,
                                            filter.accentColor.opacity(0.62)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [
                                            HUDTheme.border,
                                            HUDTheme.border
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(
                        color: selected ? filter.accentColor.opacity(0.28) : .clear,
                        radius: selected ? 7 : 0,
                        y: 2
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
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

            Spacer(minLength: 2)

            Text("\(visibleCount) 个会话")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(HUDTheme.surface.opacity(0.18))
        .animation(HUDMetrics.filterAnimation, value: selectedFilter)
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
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.shortLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(
            LinearGradient(
                colors: [
                    status.color.opacity(0.20),
                    status.color.opacity(0.065)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            HUDTheme.borderStrong,
                            status.color.opacity(0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: status.color.opacity(0.18), radius: 4, y: 1)
        .help("\(status.label) · \(confidence.label)")
    }
}

private struct PrivacyStrip: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 10))
            Text("隐私模式已开启，标题、路径、原始输入、图片和总结均已隐藏")
                .font(.system(size: 10.5, weight: .medium))
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
                .font(.system(size: 11, weight: .semibold))
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
        .font(.system(size: 10, weight: .medium))
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
            Text("AgentHUD 正在只读监听 Codex 与 Claude Code")
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(HUDTheme.controlFill)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HUDTheme.border)
            Image(systemName: "rectangle.3.group")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(HUDTheme.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

private struct BrandToggleButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BrandMark(size: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(
                    HUDTheme.controlFill,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
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
