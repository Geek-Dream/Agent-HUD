import AppKit
import SwiftUI

@MainActor
final class AISettingsWindowController: NSWindowController {
    private let onConfigurationChanged: () -> Void

    init(
        displayModel: HUDViewModel,
        onConfigurationChanged: @escaping () -> Void
    ) {
        self.onConfigurationChanged = onConfigurationChanged
        let settingsModel = AISettingsViewModel(
            onConfigurationChanged: onConfigurationChanged
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 590),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI 标题与显示设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: AISettingsView(model: settingsModel, displayModel: displayModel)
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var enabled: Bool
    @Published var endpoint: String
    @Published var model: String
    @Published var apiKeyDraft = ""
    @Published private(set) var hasStoredKey = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var statusIsError = false
    @Published private(set) var isTesting = false

    private let secretStore: AISecretStoring
    private let onConfigurationChanged: () -> Void
    private let testService = AITitleService()

    init(
        secretStore: AISecretStoring = KeychainAISecretStore(),
        onConfigurationChanged: @escaping () -> Void
    ) {
        let configuration = AIConfiguration.load()
        self.enabled = configuration.enabled
        self.endpoint = configuration.endpoint
        self.model = configuration.model
        self.secretStore = secretStore
        self.onConfigurationChanged = onConfigurationChanged
        refreshSecretState()
    }

    func refreshSecretState() {
        hasStoredKey = secretStore.apiKey() != nil
    }

    func save() {
        guard let configuration = formConfiguration() else {
            setStatus("API 地址无效，请填写 http 或 https 地址", isError: true)
            return
        }

        configuration.save()
        do {
            let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                try secretStore.saveAPIKey(key)
                apiKeyDraft = ""
            }
            refreshSecretState()
            onConfigurationChanged()
            if configuration.enabled && !hasStoredKey {
                setStatus("配置已保存；还需要填写 API Key 才能使用 AI 标题", isError: false)
            } else {
                setStatus("配置已保存", isError: false)
            }
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func deleteAPIKey() {
        do {
            try secretStore.deleteAPIKey()
            enabled = false
            var configuration = formConfiguration() ?? AIConfiguration(
                enabled: false,
                endpoint: endpoint,
                model: model
            )
            configuration.enabled = false
            configuration.save()
            apiKeyDraft = ""
            refreshSecretState()
            onConfigurationChanged()
            setStatus("API Key 已从 Keychain 删除，AI 标题已关闭", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func testConnection() {
        guard let configuration = formConfiguration() else {
            setStatus("API 地址无效，请填写 http 或 https 地址", isError: true)
            return
        }
        let draftKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = draftKey.isEmpty ? secretStore.apiKey() : draftKey else {
            setStatus("请先填写 API Key", isError: true)
            return
        }

        isTesting = true
        statusMessage = "正在测试连接…"
        statusIsError = false

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.testService.testConnection(
                    configuration: configuration,
                    apiKey: apiKey
                )
                self.isTesting = false
                self.setStatus("连接成功，AI 可以生成标题", isError: false)
            } catch {
                self.isTesting = false
                self.setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func formConfiguration() -> AIConfiguration? {
        let configuration = AIConfiguration(
            enabled: enabled,
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return configuration.chatCompletionsURL == nil ? nil : configuration
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

private struct AISettingsView: View {
    @ObservedObject var model: AISettingsViewModel
    @ObservedObject var displayModel: HUDViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.02, green: 0.38, blue: 0.92))
                    .frame(width: 38, height: 38)
                    .background(
                        Color(red: 0.02, green: 0.38, blue: 0.92).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 标题")
                        .font(.system(size: 17, weight: .semibold))
                    Text("根据用户最近输入和图片生成简短任务标题")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            displaySettings

            Divider()

            Toggle("启用 AI 标题", isOn: $model.enabled)
                .toggleStyle(.switch)

            settingsField("API 地址") {
                TextField("https://example.com/v1", text: $model.endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            settingsField("模型") {
                TextField("模型名称", text: $model.model)
                    .textFieldStyle(.roundedBorder)
            }

            settingsField("API Key") {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField(
                        model.hasStoredKey ? "已保存，留空则保持不变" : "填写 API Key",
                        text: $model.apiKeyDraft
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9.5))
                        Text(model.hasStoredKey ? "密钥已配置在 Keychain 或环境变量" : "尚未配置密钥")
                            .font(.system(size: 10.5))
                        Spacer()
                        Button("删除密钥") {
                            model.deleteAPIKey()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .disabled(!model.hasStoredKey)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if model.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else if !model.statusMessage.isEmpty {
                    Image(
                        systemName: model.statusIsError
                            ? "exclamationmark.circle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.system(size: 10.5))
                }

                Text(model.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
                    .lineLimit(2)

                Spacer()

                Button("测试连接") {
                    model.testConnection()
                }
                .disabled(model.isTesting)

                Button("保存") {
                    model.save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            Label(
                "API Key 只写入 macOS Keychain；环境变量 AGENTHUD_AI_API_KEY 可作为后备。",
                systemImage: "lock.shield"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 520, alignment: .topLeading)
        }
        .frame(width: 520, height: 590)
        .onAppear {
            model.refreshSecretState()
        }
    }

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("面板尺寸")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("恢复默认") {
                    displayModel.expandedWidth = ExpandedPanelSize.defaultWidth
                    displayModel.expandedHeight = ExpandedPanelSize.defaultHeight
                }
                .font(.system(size: 11))
            }

            dimensionSlider(
                title: "展开宽度",
                value: Binding(
                    get: { displayModel.expandedWidth },
                    set: { displayModel.expandedWidth = $0 }
                ),
                range: ExpandedPanelSize.minimumWidth...ExpandedPanelSize.maximumWidth
            )
            dimensionSlider(
                title: "展开高度",
                value: Binding(
                    get: { displayModel.expandedHeight },
                    set: { displayModel.expandedHeight = $0 }
                ),
                range: ExpandedPanelSize.minimumHeight...ExpandedPanelSize.maximumHeight
            )

            Text("宽度上限 720，高度上限 1000；收起尺寸保持不变。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }

    private func dimensionSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11))
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func settingsField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
