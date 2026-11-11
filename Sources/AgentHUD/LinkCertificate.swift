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
        let fingerprint = try Data(contentsOf: certificateURL).sha256Hex()
        return LinkCertificate(
            certificateURL: certificateURL,
            privateKeyURL: privateKeyURL,
            fingerprint: fingerprint
        )
    }
}

enum LinkNetwork {
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
