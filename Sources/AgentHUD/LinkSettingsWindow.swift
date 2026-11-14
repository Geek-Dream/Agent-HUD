import AppKit
import CoreImage
import SwiftUI

@MainActor
final class LinkSettingsModel: ObservableObject {
    @Published var code = "------"
    @Published var expiresAt = Date()
    @Published var qrImage: NSImage?
    @Published var port = 0
    @Published var addresses: [String] = []
    @Published var ipv6Addresses: [String] = []
    @Published var copiedAddress: String?
    @Published var isRefreshing = false
    @Published var error: String?
    @Published var devices: [LinkedDevice] = []

    private let server: LinkServer

    init(server: LinkServer) {
        self.server = server
    }

    func refreshOffer() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let offer = try await server.createPairingOffer()
            code = offer.code
            expiresAt = offer.expiresAt
            port = offer.port
            addresses = offer.addresses
            ipv6Addresses = server.ipv6Addresses
            qrImage = Self.qrCode(payload: offer.payload)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshDevices() async {
        devices = await server.devicesSnapshot()
    }

    func copy(_ address: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address, forType: .string)
        copiedAddress = address
        try? await Task.sleep(for: .seconds(1.5))
        if copiedAddress == address {
            copiedAddress = nil
        }
    }

    func revoke(_ deviceId: String) async {
        await server.revoke(deviceId: deviceId)
        await refreshDevices()
    }

    func setConversation(deviceId: String, enabled: Bool) async {
        _ = await server.setConversationEnabled(deviceId: deviceId, enabled: enabled)
        await refreshDevices()
    }

    private static func qrCode(payload: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 7, y: 7)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

@MainActor
final class LinkSettingsWindowController: NSWindowController {
    init(server: LinkServer) {
        let model = LinkSettingsModel(server: server)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "手机关联"
        window.contentView = NSHostingView(rootView: LinkSettingsView(model: model))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct LinkSettingsView: View {
    @ObservedObject var model: LinkSettingsModel

    private static let accent = Color(red: 0.02, green: 0.38, blue: 0.92)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                connectionSection

                Divider()

                pairingSection

                Divider()

                deviceSection

                Label(
                    "配对码两分钟有效；每台设备都有独立、可撤销的只读令牌，仅支持文本任务下发。",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(width: 520, alignment: .topLeading)
        }
        .frame(width: 520, height: 720)
        .task {
            await model.refreshOffer()
            await model.refreshDevices()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Self.accent)
                .frame(width: 38, height: 38)
                .background(
                    Self.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("手机关联")
                    .font(.system(size: 17, weight: .semibold))
                Text("扫码或输入配对码，把手机接到这台电脑的 Agent 会话")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("连接状态")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.error == nil ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(model.error == nil ? "监听中" : "异常")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = model.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("局域网地址") {
                VStack(alignment: .leading, spacing: 6) {
                    if model.addresses.isEmpty {
                        Text(model.port == 0 ? "局域网服务尚未启动" : "未获取到可用地址")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.addresses, id: \.self) { address in
                            addressRow(address)
                        }
                    }
                }
            }

            if !model.ipv6Addresses.isEmpty {
                field("IPv6 候选地址") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.ipv6Addresses, id: \.self) { address in
                            addressRow(address)
                        }
                        Text("是否可路由取决于网络与防火墙配置。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配对码")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let image = model.qrImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
            }

            Text(model.code)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = model.expiresAt.timeIntervalSince(context.date)
                HStack(spacing: 6) {
                    Image(systemName: remaining > 0 ? "clock" : "clock.badge.exclamationmark")
                        .font(.system(size: 10.5))
                    Text(
                        remaining > 0
                            ? "有效期剩余 \(Self.countdown(remaining))"
                            : "配对码已失效，请生成新的"
                    )
                    .font(.system(size: 10.5))
                }
                .foregroundStyle(remaining > 0 ? Color.secondary : Color.orange)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Button("生成新配对码") {
                    Task { await model.refreshOffer() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshing)

                Button("刷新设备") {
                    Task { await model.refreshDevices() }
                }
                .disabled(model.isRefreshing)

                Spacer()
            }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已关联设备")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.devices.count) 台")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if model.devices.isEmpty {
                Text("还没有关联设备。用手机扫码后会自动出现在这里。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach($model.devices, id: \.id) { $device in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(device.pairedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("撤销") {
                            Task { await model.revoke(device.id) }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                    }

                    Toggle(isOn: $device.conversationEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("允许对话模式")
                                .font(.system(size: 11.5))
                            Text("开启后，该手机可向此电脑的 Agent 会话发送文本任务。")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: device.conversationEnabled) { _, enabled in
                        Task { await model.setConversation(deviceId: device.id, enabled: enabled) }
                    }
                }
                .padding(12)
                .background(
                    Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }

    private func addressRow(_ address: String) -> some View {
        HStack(spacing: 8) {
            Text(address)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button(model.copiedAddress == address ? "已复制" : "复制") {
                Task { await model.copy(address) }
            }
            .font(.system(size: 10.5))
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func field<Content: View>(
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

    private static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
