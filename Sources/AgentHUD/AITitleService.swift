import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct AITitleRequest {
    let sessionID: String
    let prompt: String
    let projectName: String
    let images: [SessionImageAttachment]

    var rawFingerprint: String {
        let imageSources = images.map { attachment in
            switch attachment.source {
            case .localPath(let path):
                return "path:\(path)"
            case .dataURL(let value):
                return "data:\(value)"
            case .unavailable:
                return "unavailable"
            }
        }
        return AITitleHash.sha256(
            ([sessionID, prompt, projectName] + imageSources).joined(separator: "\u{001F}")
        )
    }
}

struct AITitleHTTPResponse {
    let data: Data
    let statusCode: Int
}

protocol AITitleTransport {
    func send(_ request: URLRequest) async throws -> AITitleHTTPResponse
}

struct URLSessionAITitleTransport: AITitleTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> AITitleHTTPResponse {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return AITitleHTTPResponse(data: data, statusCode: statusCode)
    }
}

enum AITitleServiceError: LocalizedError {
    case invalidConfiguration
    case missingAPIKey
    case emptyPrompt
    case invalidResponse
    case httpStatus(Int)
    case backoff(until: Date)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "AI 地址或模型配置无效"
        case .missingAPIKey:
            return "尚未配置 API Key"
        case .emptyPrompt:
            return "当前会话没有可总结的用户输入"
        case .invalidResponse:
            return "AI 返回内容无法解析"
        case .httpStatus(let status):
            return "AI 请求失败（HTTP \(status)）"
        case .backoff(let date):
            return "AI 请求暂时退避，\(date.formatted(.dateTime.hour().minute())) 后重试"
        }
    }
}

private struct CachedAITitle {
    let title: String
    let createdAt: Date
}

private struct FailedAITitle {
    let retryAfter: Date
}

actor AITitleService {
    private let transport: AITitleTransport
    private let now: () -> Date
    private let failureBackoff: TimeInterval
    private var titles: [String: CachedAITitle] = [:]
    private var failures: [String: FailedAITitle] = [:]

    init(
        transport: AITitleTransport = URLSessionAITitleTransport(),
        now: @escaping () -> Date = Date.init,
        failureBackoff: TimeInterval = 300
    ) {
        self.transport = transport
        self.now = now
        self.failureBackoff = failureBackoff
    }

    func title(
        for titleRequest: AITitleRequest,
        configuration: AIConfiguration,
        apiKey: String
    ) async throws -> String {
        let prepared = try AITitleRequestFactory.prepare(titleRequest)
        let cacheKey = AITitleHash.sha256(
            [
                prepared.request.sessionID,
                prepared.request.prompt,
                prepared.request.projectName,
                configuration.chatCompletionsURL?.absoluteString ?? "",
                configuration.model,
                prepared.imageFingerprint
            ].joined(separator: "\u{001E}")
        )

        if let cached = titles[cacheKey] {
            return cached.title
        }
        if let failed = failures[cacheKey], failed.retryAfter > now() {
            throw AITitleServiceError.backoff(until: failed.retryAfter)
        }

        do {
            let request = try AITitleRequestFactory.makeURLRequest(
                prepared: prepared,
                configuration: configuration,
                apiKey: apiKey
            )
            let response = try await transport.send(request)
            guard (200..<300).contains(response.statusCode) else {
                throw AITitleServiceError.httpStatus(response.statusCode)
            }
            let rawTitle = try AITitleResponseParser.title(from: response.data)
            guard let title = AITitleOutputSanitizer.sanitize(
                rawTitle,
                originalPrompt: prepared.request.prompt,
                projectName: prepared.request.projectName
            ) else {
                throw AITitleServiceError.invalidResponse
            }

            titles[cacheKey] = CachedAITitle(title: title, createdAt: now())
            failures.removeValue(forKey: cacheKey)
            return title
        } catch {
            failures[cacheKey] = FailedAITitle(
                retryAfter: now().addingTimeInterval(failureBackoff)
            )
            throw error
        }
    }

    func testConnection(
        configuration: AIConfiguration,
        apiKey: String
    ) async throws {
        let probe = AITitleRequest(
            sessionID: "connection-test-\(UUID().uuidString)",
            prompt: "请只回复：连接正常",
            projectName: "",
            images: []
        )
        _ = try await title(
            for: probe,
            configuration: configuration,
            apiKey: apiKey
        )
    }

    func clearCache() {
        titles.removeAll()
        failures.removeAll()
    }
}

struct PreparedAITitleRequest {
    let request: AITitleRequest
    let imageDataURLs: [String]
    let imageFingerprint: String
}

enum AITitleRequestFactory {
    private static let maximumImageBytes = 8 * 1024 * 1024

    static func prepare(_ request: AITitleRequest) throws -> PreparedAITitleRequest {
        let prompt = TextTools.userPromptText(request.prompt, limit: 4_000)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !request.images.isEmpty else {
            throw AITitleServiceError.emptyPrompt
        }

        var imageDataURLs: [String] = []
        var imageHashes: [String] = []
        for attachment in request.images.prefix(6) {
            guard let dataURL = dataURL(for: attachment) else {
                continue
            }
            imageDataURLs.append(dataURL)
            imageHashes.append(AITitleHash.sha256(dataURL))
        }
        guard !prompt.isEmpty || !imageDataURLs.isEmpty else {
            throw AITitleServiceError.emptyPrompt
        }

        return PreparedAITitleRequest(
            request: AITitleRequest(
                sessionID: request.sessionID,
                prompt: prompt,
                projectName: request.projectName,
                images: request.images
            ),
            imageDataURLs: imageDataURLs,
            imageFingerprint: imageHashes.joined(separator: ":")
        )
    }

    static func makeURLRequest(
        prepared: PreparedAITitleRequest,
        configuration: AIConfiguration,
        apiKey: String
    ) throws -> URLRequest {
        guard let url = configuration.chatCompletionsURL,
              !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AITitleServiceError.invalidConfiguration
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AITitleServiceError.missingAPIKey
        }

        let projectContext = prepared.request.projectName.isEmpty
            ? ""
            : "项目名称（仅供理解，不要写进标题）：\(prepared.request.projectName)\n"
        let prompt = prepared.request.prompt.isEmpty
            ? "用户只发送了图片，请根据图片判断用户想完成的事情。"
            : prepared.request.prompt

        var userContent: [[String: Any]] = [[
            "type": "text",
            "text": "\(projectContext)用户最近一次有效输入：\n\(prompt)"
        ]]
        userContent.append(contentsOf: prepared.imageDataURLs.map { dataURL in
            [
                "type": "image_url",
                "image_url": ["url": dataURL]
            ]
        })

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": 512,
            "stream": false,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    你是任务标题总结器。根据用户最近一次输入和图片，用大白话概括用户真正想做什么。
                    只输出一个中文标题，不要解释，不要引号、Markdown、句号或冒号。
                    标题约 6 到 16 个汉字；不要照抄原句；不要写项目名；不要使用“处理某项目任务”这类泛化模板。
                    """
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func dataURL(for attachment: SessionImageAttachment) -> String? {
        switch attachment.source {
        case .dataURL(let value):
            return value
        case .localPath(let path):
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true,
               let fileSize = values.fileSize,
               fileSize > 0,
               fileSize <= maximumImageBytes,
               let data = try? Data(contentsOf: url) else {
                return nil
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "image/jpeg"
            return "data:\(mimeType);base64,\(data.base64EncodedString())"
        case .unavailable:
            return nil
        }
    }
}

enum AITitleResponseParser {
    static func title(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let choices = dictionary["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AITitleServiceError.invalidResponse
        }

        let content = JSONTools.collectText(message["content"]).joined(separator: "\n")
        guard !TextTools.normalizedWhitespace(content).isEmpty else {
            throw AITitleServiceError.invalidResponse
        }
        return content
    }
}

enum AITitleOutputSanitizer {
    static func sanitize(
        _ raw: String,
        originalPrompt: String,
        projectName: String?
    ) -> String? {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? raw

        var title = TextTools.normalizedWhitespace(firstLine)
        title = title.replacingOccurrences(of: "```", with: "")
        title = title.replacingOccurrences(of: "**", with: "")
        title = title.replacingOccurrences(of: "`", with: "")
        title = title.replacingOccurrences(
            of: #"^(标题|任务标题|总结)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        title = title.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)
                .union(CharacterSet(charactersIn: "\"'“”‘’「」『』"))
        )
        title = TextTools.normalizedWhitespace(title)

        guard title.count >= 4, title.count <= 24 else {
            return nil
        }
        guard hanCharacterCount(title) >= 4 else {
            return nil
        }
        guard !TextTools.isContinuationPrompt(title) else {
            return nil
        }
        guard !containsTechnicalNoise(title) else {
            return nil
        }

        let lowercased = title.lowercased()
        if lowercased.contains("/users/")
            || lowercased.contains("http://")
            || lowercased.contains("https://")
            || lowercased.contains("```") {
            return nil
        }
        if title.range(
            of: #"^(处理|完成|总结).{0,18}(项目)?任务$"#,
            options: .regularExpression
        ) != nil {
            return nil
        }

        if let projectName {
            let normalizedProject = TextTools.normalizedWhitespace(projectName).lowercased()
            if normalizedProject.count >= 2, lowercased.contains(normalizedProject) {
                return nil
            }
        }

        let normalizedPrompt = TextTools.normalizedWhitespace(originalPrompt)
        if title == normalizedPrompt {
            return nil
        }
        if normalizedPrompt.count > title.count + 4,
           normalizedPrompt.contains(title),
           title.count >= 10 {
            return nil
        }
        return title
    }

    private static func containsTechnicalNoise(_ value: String) -> Bool {
        value.contains("<environment_context>")
            || value.contains("<hook_prompt")
            || value.range(
                of: #"(?i)\.(md|swift|tsx?|jsx?|jsonl?|py|go|java|css|html|xml|yaml|yml)(?:$|[^a-z0-9])"#,
                options: .regularExpression
            ) != nil
    }

    private static func hanCharacterCount(_ value: String) -> Int {
        value.unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0x4E00...0x9FFF).contains(Int(scalar.value))
        }.count
    }
}

enum AITitleHash {
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
