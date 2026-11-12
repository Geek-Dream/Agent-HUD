import AppKit
import CoreImage
import SwiftUI

@MainActor
final class LinkSettingsModel: ObservableObject {
    @Published var code = "------"
    @Published var expiresAt = Date()
    @Published var qrImage: NSImage?
    @Published var serviceText = "局域网服务尚未启动"
    @Published var ipv6Text = ""
    @Published var error: String?
    @Published var devices: [LinkedDevice] = []

    private let server: LinkServer

    init(server: LinkServer) {
        self.server = server
    }

    func refreshOffer() async {
        do {
            let offer = try await server.createPairingOffer()
            code = offer.code
            expiresAt = offer.expiresAt
            serviceText = "监听端口 \(offer.port) · \(offer.addresses.joined(separator: " / "))"
            ipv6Text = LinkNetwork.ipv6Addresses().joined(separator: "\n")
            qrImage = Self.qrCode(payload: offer.payload)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshDevices() async {
        devices = await server.devicesSnapshot()
    }

    func revoke(_ deviceId: String) async {
        await server.revoke(deviceId: deviceId)
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
    private let model: LinkSettingsModel

    init(server: LinkServer) {
        model = LinkSettingsModel(server: server)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
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
        Task { await model.refreshOffer() }
        Task { await model.refreshDevices() }
    }
}

private struct LinkSettingsView: View {
    @ObservedObject var model: LinkSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("使用手机扫码或输入验证码。配对码两分钟有效，每台设备都有独立、可撤销的只读令牌。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(model.serviceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !model.ipv6Text.isEmpty {
                    Text("IPv6 候选地址（是否可路由取决于网络与防火墙）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.ipv6Text)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let image = model.qrImage {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 250, height: 250)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }

                Text(model.code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Text("有效期至 \(model.expiresAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                if let error = model.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("生成新配对码") {
                        Task { await model.refreshOffer() }
                    }
                    Button("刷新设备") {
                        Task { await model.refreshDevices() }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                Text("已关联设备")
                    .font(.headline)
                ForEach(model.devices, id: \.id) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.pairedAt.formatted())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("撤销", role: .destructive) {
                            Task { await model.revoke(device.id) }
                        }
                    }
                }

                Text("首版仅提供只读监控，不发送 API Key、完整路径、原始日志或图片。请在防火墙中仅允许专用网络访问。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .task {
            await model.refreshOffer()
            await model.refreshDevices()
        }
    }
}
