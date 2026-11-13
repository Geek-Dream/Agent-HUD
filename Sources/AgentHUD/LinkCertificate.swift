import Darwin
import Foundation

struct LinkCertificate {
    let certificateURL: URL
    let privateKeyURL: URL
    let fingerprint: String

    static func loadOrCreate(directory: URL) throws -> LinkCertificate {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let certificateURL = directory.appendingPathComponent("certificate.pem")
        let privateKeyURL = directory.appendingPathComponent("private-key.pem")
        if !FileManager.default.fileExists(atPath: certificateURL.path)
            || !FileManager.default.fileExists(atPath: privateKeyURL.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = [
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1825", "-nodes",
                "-subj", "/CN=AgentHUD Local",
                "-keyout", privateKeyURL.path,
                "-out", certificateURL.path
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "AgentHUD.Link.Certificate", code: Int(process.terminationStatus))
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: privateKeyURL.path
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["x509", "-in", certificateURL.path, "-outform", "DER"]
        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        try process.run()
        let der = try standardOutput.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !der.isEmpty else {
            throw NSError(domain: "AgentHUD.Link.Certificate", code: Int(process.terminationStatus))
        }
        let fingerprint = der.sha256Hex()
        return LinkCertificate(
            certificateURL: certificateURL,
            privateKeyURL: privateKeyURL,
            fingerprint: fingerprint
        )
    }
}

enum LinkNetwork {
    struct IPv6Address {
        let value: String
        let interfaceName: String
        let isGlobal: Bool
        let isUniqueLocal: Bool
        let isLinkLocal: Bool
    }

    /// 手机端会按顺序逐个尝试这些地址，所以最可能连通的地址必须排在最前面。
    ///
    /// - 链路本地地址（fe80::/10）在手机上无法使用：访问它需要 `%en0` 这样的网卡 zone，
    ///   而 Dart 的 `Uri` 会把 `%` 编码成 `%25`，请求必然失败。
    /// - `vmenet*` 是虚拟机内部网卡，局域网里的手机不可达。
    /// - 全球单播地址优先于 ULA（fc00::/7）：ULA 通常来自 Internet 共享（bridge100）
    ///   或虚拟机仅主机网络（bridge101），手机拿不到这些网段。
    static func ipv6Addresses() -> [String] {
        interfaceIPv6Addresses()
            .filter { !$0.isLinkLocal && !$0.value.hasPrefix("::1") }
            .filter { !$0.interfaceName.hasPrefix("vmenet") }
            .sorted {
                if $0.isGlobal != $1.isGlobal { return $0.isGlobal }
                if $0.isUniqueLocal != $1.isUniqueLocal { return $0.isUniqueLocal }
                let lhsBridge = $0.interfaceName.hasPrefix("bridge")
                let rhsBridge = $1.interfaceName.hasPrefix("bridge")
                if lhsBridge != rhsBridge { return !lhsBridge }
                return $0.value < $1.value
            }
            .map(\.value)
            .uniqued()
            .prefix(4)
            .map { $0 }
    }

    static func interfaceIPv6Addresses() -> [IPv6Address] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        var output: [IPv6Address] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET6),
                  let interfaceName = interface.ifa_name else {
                continue
            }
            let name = String(cString: interfaceName)
            guard !name.hasPrefix("lo"), !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"), !name.hasPrefix("llw") else {
                continue
            }
            var bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr.__u6_addr.__u6_addr8
            }
            let isLinkLocal = bytes.0 == 0xfe && bytes.1 & 0xc0 == 0x80
            let isUniqueLocal = bytes.0 & 0xfe == 0xfc
            let isGlobal = bytes.0 & 0xe0 == 0x20
            guard isLinkLocal || isUniqueLocal || isGlobal else { continue }
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &bytes, &text, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                continue
            }
            let value = String(cString: text) + (isLinkLocal ? "%\(name)" : "")
            output.append(
                IPv6Address(
                    value: value,
                    interfaceName: name,
                    isGlobal: isGlobal,
                    isUniqueLocal: isUniqueLocal,
                    isLinkLocal: isLinkLocal
                )
            )
        }
        return output
    }

    static func localIPv4Addresses() -> [String] {
        Host.current().addresses
            .filter { address in
                let parts = address.split(separator: ".")
                return parts.count == 4
                    && parts.allSatisfy { UInt8($0) != nil }
                    && !address.hasPrefix("127.")
                    && !address.hasPrefix("169.254.")
            }
            .sorted { lhs, rhs in
                if isPrivate(lhs) != isPrivate(rhs) { return isPrivate(lhs) }
                return lhs < rhs
            }
            .uniqued()
            .prefix(6)
            .map { $0 }
    }

    private static func isPrivate(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        guard parts.count == 4, let first = UInt8(parts[0]), let second = UInt8(parts[1]) else {
            return false
        }
        return first == 10
            || first == 192 && second == 168
            || first == 172 && (16...31).contains(second)
    }
}

private extension Sequence where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
