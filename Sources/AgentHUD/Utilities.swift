import Foundation

private struct TitleConcept {
    let phrase: String
    let terms: [String]
    let weight: Int
}

enum DateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }

        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1_000)
            }
            return Date(timeIntervalSince1970: seconds)
        }

        guard let string = value as? String else {
            return nil
        }

        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        if let date = standardFormatter.date(from: string) {
            return date
        }

        if let seconds = Double(string) {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1_000)
            }
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}

enum TextTools {
    private static let boilerplatePrefixes = [
        "<environment_context>",
        "<permissions",
        "# AGENTS.md",
        "## AGENTS.md",
        "You are Codex",
        "You are an AI assistant"
    ]

    private static let continuationPrompts: Set<String> = [
        "继续", "继续吧", "请继续", "请继续吧", "继续做", "继续做吧",
        "继续处理", "继续处理吧",
        "接着", "接着来", "接着做", "往下", "下一步", "可以继续",
        "好", "好的", "可以", "开始吧", "做吧", "干吧", "嗯", "是的",
        "确认", "确认一下", "已确认", "收到", "知道了", "明白", "了解了",
        "continue", "continue please", "please continue",
        "go on", "keep going", "proceed", "next",
        "ok", "okay", "yes", "do it", "go ahead"
    ]

    private static let titleLeadIns = [
        "这是一个空项目",
        "现在",
        "你帮我",
        "帮我",
        "请你",
        "请帮忙",
        "麻烦你",
        "麻烦",
        "需要你",
        "你",
        "先"
    ]

    private static let titleConcepts: [TitleConcept] = [
        TitleConcept(
            phrase: "自动标题",
            terms: ["自动标题", "自动命名", "标题", "命名", "备注"],
            weight: 8
        ),
        TitleConcept(
            phrase: "后台运行方式",
            terms: ["后台", "前台", "焦点", "鼠标", "键盘", "操控"],
            weight: 8
        ),
        TitleConcept(
            phrase: "拖动与固定",
            terms: ["拖动", "拖拽", "移动", "固定"],
            weight: 8
        ),
        TitleConcept(
            phrase: "状态配色",
            terms: ["配色", "颜色", "霓虹", "半透明", "透光", "看不清", "太淡"],
            weight: 7
        ),
        TitleConcept(
            phrase: "缩放控件",
            terms: ["放大", "缩小", "缩放"],
            weight: 7
        ),
        TitleConcept(
            phrase: "折叠动画",
            terms: ["折叠", "收起", "丝滑"],
            weight: 7
        ),
        TitleConcept(
            phrase: "启动器",
            terms: ["启动器", "启动的东西", "点击可以启动", "点击启动"],
            weight: 8
        ),
        TitleConcept(
            phrase: "Agent筛选",
            terms: ["筛选项", "筛选", "过滤", "codex", "claude", "pi", "opencode"],
            weight: 7
        ),
        TitleConcept(
            phrase: "会话数量统计",
            terms: ["数据对不上", "数量", "统计", "显示全部", "多少个"],
            weight: 8
        ),
        TitleConcept(
            phrase: "界面动画",
            terms: ["动画", "过渡"],
            weight: 5
        ),
        TitleConcept(
            phrase: "浮窗列表",
            terms: ["浮窗", "列表", "面板"],
            weight: 5
        ),
        TitleConcept(
            phrase: "任务详情",
            terms: ["详情", "总结", "完成说明"],
            weight: 4
        ),
        TitleConcept(
            phrase: "页面布局",
            terms: ["页面", "布局", "界面"],
            weight: 4
        ),
        TitleConcept(
            phrase: "需求文档",
            terms: ["需求", "文档", "requirements"],
            weight: 4
        ),
        TitleConcept(
            phrase: "测试验证",
            terms: ["测试", "验证", "检查"],
            weight: 3
        ),
        TitleConcept(
            phrase: "接口",
            terms: ["接口", "api"],
            weight: 3
        )
    ]

    static func normalizedWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func meaningfulPrompt(_ value: String) -> String? {
        let stripped = stripInjectedPromptContent(value)
        guard !stripped.isEmpty else {
            return nil
        }

        var meaningfulLines: [String] = []
        for line in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let candidate = normalizedWhitespace(String(line))
            guard !candidate.isEmpty else { continue }
            guard !candidate.hasPrefix("```") else { continue }
            guard !boilerplatePrefixes.contains(where: { candidate.hasPrefix($0) }) else {
                continue
            }
            guard !candidate.hasPrefix("<") else { continue }
            guard !candidate.hasPrefix("[") || candidate.count > 20 else { continue }
            meaningfulLines.append(candidate)
        }

        let joined = normalizedWhitespace(meaningfulLines.joined(separator: " "))
        guard !joined.isEmpty else {
            return nil
        }
        return String(joined.prefix(600))
    }

    static func userPromptText(_ value: String, limit: Int = 12_000) -> String {
        let stripped = stripInjectedPromptContentPreservingLayout(value)
        guard !stripped.isEmpty else {
            return ""
        }
        return String(stripped.prefix(limit))
    }

    static func isContinuationPrompt(_ value: String) -> Bool {
        let normalized = normalizedWhitespace(value)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        return continuationPrompts.contains(normalized)
    }

    static func titleLine(_ value: String, limit: Int = 72) -> String {
        let cleaned = meaningfulPrompt(value) ?? normalizedWhitespace(value)
        guard !cleaned.isEmpty else {
            return "未命名任务"
        }

        let withoutMarkdown = cleaned
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#-* >"))

        return String(withoutMarkdown.prefix(limit))
    }

    static func automaticTaskTitle(
        rawPrompt: String?,
        projectName: String? = nil,
        suggestedTitle: String? = nil,
        limit: Int = 30
    ) -> String {
        let project = normalizedProjectName(projectName)
        let raw = rawPrompt.map(normalizedWhitespace) ?? ""

        if !raw.isEmpty, !isContinuationPrompt(raw) {
            return promptBasedTitle(raw: raw, project: project, limit: limit)
        }

        if let suggestedTitle,
           let candidate = usableAutomaticTitle(suggestedTitle, rawPrompt: raw) {
            return String(candidate.prefix(limit))
        }

        return projectFallback(project)
    }

    private static func promptBasedTitle(raw: String, project: String?, limit: Int) -> String {
        let lowercased = raw.lowercased()
        let projectComponent = project.map { "\($0)项目" } ?? ""
        let promptLead = stripTitleLeadIns(cleanTaskText(raw))
        let mentionsOSS = lowercased.contains("oss")
            || lowercased.contains("对象存储")
        let mentionsScript = lowercased.contains("脚本")
            || lowercased.contains(".sh")
            || lowercased.contains("shell")
        let mentionsDelete = lowercased.contains("删除")
            || lowercased.contains("移除")
            || lowercased.contains("delete")
            || lowercased.contains("remove")
        if mentionsOSS && mentionsScript && mentionsDelete {
            return String("脚本是否可以操作oss删除".prefix(limit))
        }

        let mentionsDocument = lowercased.contains("requirements")
            || lowercased.contains(".md")
            || raw.contains("文档")
            || raw.contains("需求")
        let asksToReadAtStart = ["读取", "阅读", "理解", "梳理"].contains {
            promptLead.hasPrefix($0)
        }
        if mentionsDocument && asksToReadAtStart {
            return String("梳理\(projectComponent)需求".prefix(limit))
        }

        let logLead = String(promptLead.prefix(80)).lowercased()
        let mentionsLogs = logLead.contains("日志")
            || logLead.contains("报错")
            || logLead.contains("异常")
            || logLead.contains("error")
            || logLead.contains("bug")
        if mentionsLogs {
            let action = raw.contains("修复") ? "修复" : "查询一下"
            return String("\(action)\(projectComponent)日志报错详情".prefix(limit))
        }

        let cleaned = stripTitleLeadIns(cleanTaskText(raw))
        guard !cleaned.isEmpty, !isContinuationPrompt(cleaned) else {
            return projectFallback(project)
        }

        let conciseLimit = min(limit, 28)
        if isAlreadyConciseTitle(cleaned, limit: conciseLimit) {
            return String(cleaned.prefix(limit))
        }

        let action = inferredTitleAction(cleaned)
        if let object = inferredTitleObject(cleaned),
           !object.isEmpty,
           object != project {
            return composeTitle(
                action: action,
                projectComponent: projectComponent,
                object: object,
                limit: limit
            )
        }

        return projectFallback(project, action: action)
    }

    static func sentence(_ value: String, limit: Int = 360) -> String {
        let cleaned = normalizedWhitespace(value)
        guard !cleaned.isEmpty else {
            return "没有可用的完成说明。"
        }
        return String(cleaned.prefix(limit))
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let clean = normalizedWhitespace(value)
            guard !clean.isEmpty, seen.insert(clean).inserted else {
                return false
            }
            return true
        }
    }

    private static func usableAutomaticTitle(_ value: String, rawPrompt: String) -> String? {
        let cleaned = cleanTaskText(value)
        guard cleaned.count >= 2, cleaned.count <= 36 else {
            return nil
        }
        guard !isContinuationPrompt(cleaned), !containsTechnicalNoise(value) else {
            return nil
        }
        guard !hasLongPromptLead(cleaned) else {
            return nil
        }

        let normalizedRaw = normalizedWhitespace(rawPrompt)
        if !normalizedRaw.isEmpty {
            if cleaned == normalizedRaw {
                return nil
            }
            if cleaned.count >= 18,
               normalizedRaw.contains(cleaned),
               normalizedRaw.count > cleaned.count + 6 {
                return nil
            }
        }

        return stripTerminalPunctuation(cleaned)
    }

    private static func cleanTaskText(_ value: String) -> String {
        var text = stripInjectedPromptContent(value)
        text = replacingMatches(pattern: "(?is)```.*?```", in: text)
        text = replacingMatches(pattern: "(?is)<[^>]+>", in: text)
        text = replacingMatches(pattern: "(?i)https?://\\S+", in: text)
        text = replacingMatches(
            pattern: "(?i)/(?:Users|private|tmp|var|opt|Volumes)/\\S+",
            in: text
        )
        text = replacingMatches(pattern: "(?i)[A-Z]:\\\\[^\\s]+", in: text)
        text = replacingMatches(
            pattern: "(?i)\\b[\\w.-]+\\.(?:md|swift|tsx?|jsx?|jsonl?|py|go|java|css|html|xml|yaml|yml)\\b",
            in: text
        )
        text = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: " ")
            .replacingOccurrences(of: ">", with: " ")
        return normalizedWhitespace(text)
    }

    private static func stripTitleLeadIns(_ value: String) -> String {
        var text = value
        var removedPrefix = true

        while removedPrefix {
            removedPrefix = false
            text = text.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
            )
            for prefix in titleLeadIns where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
                removedPrefix = true
                break
            }
        }

        return stripTerminalPunctuation(text)
    }

    private static func inferredTitleAction(_ value: String) -> String {
        let lowercased = value.lowercased()
        let fixTerms = [
            "修复", "解决", "不可", "无法", "对不上", "不正确",
            "不对", "报错", "异常", "问题", "bug", "失败", "操控",
            "前台工作"
        ]
        if fixTerms.contains(where: { lowercased.contains($0) }) {
            return "修复"
        }

        let optimizeTerms = [
            "优化", "完善", "调整", "提升", "确保", "稍微", "太丑", "太淡",
            "看不清", "不好", "影响", "修改为", "改成"
        ]
        if optimizeTerms.contains(where: { lowercased.contains($0) }) {
            return "优化"
        }

        let addTerms = ["搞个", "加个", "弄个", "做一个", "新增", "添加"]
        if addTerms.contains(where: { lowercased.contains($0) }) {
            return "添加"
        }

        if value.contains("实现") || value.contains("开发") || value.contains("搭建")
            || value.contains("创建") {
            return "实现"
        }
        if value.contains("启动") || value.contains("运行") || value.contains("部署") {
            return "启动"
        }
        if value.contains("测试") || value.contains("验证") || value.contains("检查")
            || value.contains("核对") {
            return "检查"
        }
        if value.contains("查询") || value.contains("分析") || value.contains("排查")
            || value.contains("定位") || value.contains("看看") || value.contains("为啥")
            || value.contains("为什么") {
            return "查询"
        }
        if value.contains("读取") || value.contains("阅读") || value.contains("理解")
            || value.contains("梳理") {
            return "梳理"
        }
        return "处理"
    }

    private static func inferredTitleObject(_ value: String) -> String? {
        let lowercased = value.lowercased()
        let hasDrag = ["拖动", "拖拽", "移动", "固定"].contains {
            lowercased.contains($0)
        }
        let hasColor = ["配色", "颜色", "霓虹", "半透明", "透光", "看不清", "太淡"].contains {
            lowercased.contains($0)
        }
        if hasDrag && hasColor {
            return "拖动与配色"
        }

        let hasZoom = ["放大", "缩小", "缩放"].contains {
            lowercased.contains($0)
        }
        let hasFold = ["折叠", "收起"].contains {
            lowercased.contains($0)
        }
        let hasAnimation = ["动画", "过渡", "丝滑"].contains {
            lowercased.contains($0)
        }
        if hasZoom && hasAnimation {
            return "缩放动画"
        }
        if hasFold && hasAnimation {
            return "折叠动画"
        }

        let ranked = titleConcepts.compactMap { concept -> (TitleConcept, Int, Int)? in
            let matched = concept.terms.filter { lowercased.contains($0) }
            guard !matched.isEmpty else {
                return nil
            }
            let firstIndex = matched.compactMap { lowercased.range(of: $0)?.lowerBound }
                .min()
                .map { lowercased.distance(from: lowercased.startIndex, to: $0) }
                ?? Int.max
            return (concept, concept.weight + matched.count * 2, firstIndex)
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            return lhs.2 < rhs.2
        }

        if let concept = ranked.first?.0 {
            return concept.phrase
        }

        var candidate = value
        let removablePrefixes = [
            "查询", "分析", "排查", "定位", "看看", "检查", "核对", "修改",
            "调整", "优化", "完善", "实现", "开发", "搭建", "新增", "添加",
            "创建", "修复", "启动", "运行", "部署", "读取", "阅读", "理解",
            "梳理", "一下", "刚刚", "当前", "这个", "那个"
        ]
        var changed = true
        while changed {
            changed = false
            candidate = candidate.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
                    .union(.punctuationCharacters)
            )
            for prefix in removablePrefixes where candidate.hasPrefix(prefix) {
                candidate.removeFirst(prefix.count)
                changed = true
                break
            }
        }

        candidate = stripTerminalPunctuation(candidate)
        guard !candidate.isEmpty, candidate.count <= 18 else {
            return nil
        }
        return candidate
    }

    private static func isAlreadyConciseTitle(_ value: String, limit: Int) -> Bool {
        guard value.count <= limit else {
            return false
        }

        let clearActionPrefixes = [
            "完善", "设计", "实现", "修复", "优化", "检查", "查询",
            "添加", "新增", "创建", "启动", "梳理", "验证", "调整",
            "完成", "处理", "分析", "排查", "定位", "读取", "阅读", "理解",
            "增加"
        ]
        guard clearActionPrefixes.contains(where: { value.hasPrefix($0) }) else {
            return false
        }

        let vagueTerms = [
            "这个", "那个", "东西", "一下", "刚刚", "为什么", "为啥",
            "问题", "不可", "不能", "无法", "对不上", "不好", "太丑", "太淡"
        ]
        return !vagueTerms.contains(where: { value.contains($0) })
    }

    private static func composeTitle(
        action: String,
        projectComponent: String,
        object: String,
        limit: Int
    ) -> String {
        let withProject = "\(action)\(projectComponent)\(object)"
        if withProject.count <= limit {
            return withProject
        }

        let withoutProject = "\(action)\(object)"
        if withoutProject.count <= limit {
            return withoutProject
        }
        return String(withProject.prefix(limit))
    }

    private static func stripInjectedPromptContentPreservingLayout(_ value: String) -> String {
        var text = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if normalizedWhitespace(text).hasPrefix("# AGENTS.md")
            || normalizedWhitespace(text).hasPrefix("## AGENTS.md") {
            return ""
        }

        text = replacingMatches(
            pattern: "(?is)<environment_context>.*?</environment_context>",
            in: text
        )
        text = replacingMatches(
            pattern: "(?is)<permissions[^>]*>.*?</permissions>",
            in: text
        )
        text = replacingMatches(
            pattern: "(?is)<hook_prompt[^>]*>.*?</hook_prompt>",
            in: text
        )
        text = replacingMatches(
            pattern: "(?is)<image[^>]*>.*?</image>",
            in: text
        )
        text = replacingMatches(pattern: "(?is)</?image[^>]*>", in: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripInjectedPromptContent(_ value: String) -> String {
        normalizedWhitespace(stripInjectedPromptContentPreservingLayout(value))
    }

    private static func normalizedProjectName(_ value: String?) -> String? {
        guard var name = value.map(normalizedWhitespace), !name.isEmpty else {
            return nil
        }
        if name.contains("/") {
            name = URL(fileURLWithPath: name).lastPathComponent
        }
        if name.hasSuffix(".git") {
            name.removeLast(4)
        }
        guard !name.isEmpty, name != "未知项目" else {
            return nil
        }
        return String(name.prefix(24))
    }

    private static func projectFallback(_ project: String?, action: String = "处理") -> String {
        guard let project else {
            return "\(action)项目任务"
        }
        return "\(action)\(project)项目任务"
    }

    private static func containsTechnicalNoise(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("/users/")
            || lowercased.contains("http://")
            || lowercased.contains("https://")
            || value.contains("<environment_context>")
            || value.contains("```")
    }

    private static func hasLongPromptLead(_ value: String) -> Bool {
        value.hasPrefix("这是一个空项目")
            || value.hasPrefix("现在，")
            || value.hasPrefix("现在,")
    }

    private static func stripTerminalPunctuation(_ value: String) -> String {
        value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)
        )
    }

    private static func replacingMatches(pattern: String, in value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: " "
        )
    }
}

enum SessionAttachmentParser {
    private static let maxAttachmentCount = 6
    private static let maxImageBytes = 8 * 1024 * 1024
    private static let maxBase64Characters = ((maxImageBytes + 2) / 3) * 4

    static func codexImages(from content: Any?) -> [SessionImageAttachment] {
        guard let parts = JSONTools.array(content) else {
            return []
        }

        var attachments: [SessionImageAttachment] = []
        for part in parts {
            guard attachments.count < maxAttachmentCount,
                  let part = JSONTools.dictionary(part) else {
                continue
            }

            let type = (JSONTools.string(part["type"]) ?? "").lowercased()
            if type == "input_image" {
                if let dataURL = JSONTools.string(part["image_url"]),
                   let normalized = validatedDataURL(dataURL) {
                    attachments.append(makeAttachment(
                        provider: "codex",
                        index: attachments.count,
                        source: .dataURL(normalized),
                        label: nil
                    ))
                }
            } else if type == "local_image" {
                if let path = JSONTools.string(part["path"]),
                   let normalized = validatedLocalPath(path) {
                    attachments.append(makeAttachment(
                        provider: "codex",
                        index: attachments.count,
                        source: .localPath(normalized),
                        label: URL(fileURLWithPath: normalized).lastPathComponent
                    ))
                }
            }
        }
        return attachments
    }

    static func claudeImages(from content: Any?) -> [SessionImageAttachment] {
        guard let parts = JSONTools.array(content) else {
            return []
        }

        var attachments: [SessionImageAttachment] = []
        for part in parts {
            guard attachments.count < maxAttachmentCount,
                  let part = JSONTools.dictionary(part),
                  (JSONTools.string(part["type"]) ?? "").lowercased() == "image",
                  let source = JSONTools.dictionary(part["source"]),
                  (JSONTools.string(source["type"]) ?? "").lowercased() == "base64",
                  let mediaType = JSONTools.string(source["media_type"]),
                  let data = JSONTools.string(source["data"]),
                  let dataURL = validatedBase64Image(mediaType: mediaType, data: data) else {
                continue
            }

            attachments.append(makeAttachment(
                provider: "claude",
                index: attachments.count,
                source: .dataURL(dataURL),
                label: nil
            ))
        }
        return attachments
    }

    private static func makeAttachment(
        provider: String,
        index: Int,
        source: SessionImageSource,
        label: String?
    ) -> SessionImageAttachment {
        SessionImageAttachment(
            id: "\(provider):image:\(index)",
            source: source,
            label: label
        )
    }

    private static func validatedDataURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("data:image/"),
              let separator = lowercased.range(of: ";base64,") else {
            return nil
        }

        let metadata = lowercased[..<separator.lowerBound]
        let allowedTypes = [
            "data:image/png",
            "data:image/jpeg",
            "data:image/jpg",
            "data:image/webp",
            "data:image/gif",
            "data:image/heic",
            "data:image/heif"
        ]
        guard allowedTypes.contains(String(metadata)) else {
            return nil
        }

        let payloadStart = separator.upperBound
        let payload = trimmed[payloadStart...]
        guard !payload.isEmpty,
              payload.count <= maxBase64Characters,
              let decoded = Data(base64Encoded: String(payload), options: .ignoreUnknownCharacters),
              !decoded.isEmpty,
              decoded.count <= maxImageBytes else {
            return nil
        }
        return trimmed
    }

    private static func validatedBase64Image(mediaType: String, data: String) -> String? {
        let normalizedType = mediaType.lowercased()
        let allowedTypes = [
            "image/png",
            "image/jpeg",
            "image/jpg",
            "image/webp",
            "image/gif",
            "image/heic",
            "image/heif"
        ]
        guard allowedTypes.contains(normalizedType),
              !data.isEmpty,
              data.count <= maxBase64Characters,
              let decoded = Data(base64Encoded: data, options: .ignoreUnknownCharacters),
              !decoded.isEmpty,
              decoded.count <= maxImageBytes else {
            return nil
        }
        return "data:\(normalizedType);base64,\(data)"
    }

    private static func validatedLocalPath(_ value: String) -> String? {
        let expanded = (value as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            return nil
        }

        let url = URL(fileURLWithPath: expanded)
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ), values.isRegularFile == true,
           (values.fileSize ?? 0) <= maxImageBytes else {
            return nil
        }
        return url.path
    }
}

enum LogFileReader {
    private struct PromptLineCache {
        let fileSize: UInt64
        let lines: [String]
    }

    private static let promptCacheLock = NSLock()
    private static var promptLineCache: [String: PromptLineCache] = [:]

    static func readJSONLines(
        from url: URL,
        headBytes: Int = 96 * 1024,
        tailBytes: Int = 768 * 1024
    ) throws -> [[String: Any]] {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        let fileSize = size?.intValue ?? 0

        var chunks: [String] = []

        if fileSize <= tailBytes {
            chunks.append(try readAll(url: url))
        } else {
            chunks.append(try readPrefix(url: url, maxBytes: headBytes))
            chunks.append(try readSuffix(url: url, maxBytes: tailBytes))
        }
        chunks.append(try latestPromptLines(from: url, fileSize: UInt64(fileSize)).joined(separator: "\n"))

        var seen = Set<String>()
        var records: [[String: Any]] = []

        for chunk in chunks {
            for line in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
                let string = String(line)
                guard seen.insert(string).inserted else { continue }
                guard let data = string.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dictionary = object as? [String: Any] else {
                    continue
                }
                records.append(dictionary)
            }
        }

        return records
    }

    private static func latestPromptLines(from url: URL, fileSize: UInt64) throws -> [String] {
        let key = url.path
        promptCacheLock.lock()
        let cached = promptLineCache[key]
        promptCacheLock.unlock()

        if let cached, cached.fileSize == fileSize {
            return cached.lines
        }

        let lines: [String]
        if let cached, cached.fileSize < fileSize {
            let appended = try readPromptLines(
                from: url,
                startingAt: cached.fileSize,
                preservingFirstPartialLine: false
            )
            lines = Array((cached.lines + appended).suffix(8))
        } else {
            lines = try scanBackwardForPromptLines(from: url, fileSize: fileSize, limit: 8)
        }

        promptCacheLock.lock()
        promptLineCache[key] = PromptLineCache(fileSize: fileSize, lines: lines)
        promptCacheLock.unlock()
        return lines
    }

    private static func scanBackwardForPromptLines(
        from url: URL,
        fileSize: UInt64,
        limit: Int
    ) throws -> [String] {
        guard fileSize > 0 else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1024
        var position = fileSize
        var pending = Data()
        var found: [String] = []

        while position > 0, found.count < limit {
            let readSize = min(chunkSize, position)
            position -= readSize
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: Int(readSize)) ?? Data()
            var combined = chunk
            combined.append(pending)

            var lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
            if position > 0, !lines.isEmpty {
                pending = Data(lines.removeFirst())
            } else {
                pending = Data()
            }

            for lineData in lines.reversed() {
                let line = String(decoding: lineData, as: UTF8.self)
                guard isUserPromptLine(line) else {
                    continue
                }
                found.append(line)
                if found.count >= limit {
                    break
                }
            }
        }

        if position == 0, found.count < limit, !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            if isUserPromptLine(line) {
                found.append(line)
            }
        }

        return found
    }

    private static func readPromptLines(
        from url: URL,
        startingAt offset: UInt64,
        preservingFirstPartialLine: Bool
    ) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)

        if preservingFirstPartialLine, !lines.isEmpty {
            lines.removeFirst()
        }

        return lines.compactMap { lineData in
            let line = String(decoding: lineData, as: UTF8.self)
            return isUserPromptLine(line) ? line : nil
        }
    }

    private static func isUserPromptLine(_ line: String) -> Bool {
        guard line.contains("\"role\":\"user\"") || line.contains("\"type\":\"user\"") else {
            return false
        }
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let record = object as? [String: Any] else {
            return false
        }

        if record["type"] as? String == "user" {
            return true
        }

        guard record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "message" else {
            return false
        }
        return payload["role"] as? String == "user"
    }

    private static func readAll(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func readPrefix(url: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func readSuffix(url: URL, maxBytes: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        guard end > 0 else { return "" }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try handle.seek(toOffset: start)
        var data = try handle.readToEnd() ?? Data()

        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data = data.dropFirst(newline + 1)
        }

        return String(decoding: data, as: UTF8.self)
    }
}

enum JSONTools {
    static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func array(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func collectText(_ value: Any?) -> [String] {
        if let string = value as? String {
            return [string]
        }

        if let array = value as? [Any] {
            return array.flatMap(collectText)
        }

        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["text", "content", "message", "output_text", "input_text"]
            var values: [String] = []
            for key in preferredKeys {
                if let child = dictionary[key] {
                    values.append(contentsOf: collectText(child))
                }
            }
            if !values.isEmpty {
                return values
            }
        }

        return []
    }

    static func filePaths(from value: Any?) -> [String] {
        var results: [String] = []

        if let dictionary = value as? [String: Any] {
            for key in ["file_path", "path", "notebook_path", "cwd"] {
                if let path = dictionary[key] as? String, path.hasPrefix("/") {
                    results.append(path)
                }
            }
            for child in dictionary.values {
                results.append(contentsOf: filePaths(from: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                results.append(contentsOf: filePaths(from: child))
            }
        }

        return TextTools.unique(results)
    }
}

enum ActionDescription {
    static func describe(toolName: String?, detail: String? = nil) -> String {
        guard let toolName, !toolName.isEmpty else {
            return detail ?? "正在处理任务"
        }

        let normalized = toolName.lowercased()
        let label: String

        if normalized.contains("apply_patch") || normalized.contains("edit") || normalized.contains("write") {
            label = "正在修改文件"
        } else if normalized.contains("read") || normalized.contains("open") {
            label = "正在读取文件"
        } else if normalized.contains("grep") || normalized.contains("search") || normalized.contains("glob") {
            label = "正在搜索代码"
        } else if normalized.contains("bash") || normalized.contains("shell") || normalized.contains("exec") || normalized.contains("command") {
            label = "正在运行命令"
        } else if normalized.contains("test") {
            label = "正在验证改动"
        } else if normalized.contains("git") {
            label = "正在查看 Git"
        } else if normalized.contains("web") || normalized.contains("fetch") {
            label = "正在查询资料"
        } else {
            label = "正在使用 \(toolName)"
        }

        guard let detail = detail.flatMap(TextTools.meaningfulPrompt), !detail.isEmpty else {
            return label
        }

        return "\(label) · \(detail)"
    }

    static func readableAction(_ raw: String) -> String {
        let value = TextTools.titleLine(raw, limit: 86)
        return value.isEmpty ? "处理任务" : value
    }
}

extension TimeInterval {
    var compactDuration: String {
        let total = max(0, Int(self))
        if total < 60 {
            return "\(total)秒"
        }
        if total < 3_600 {
            return "\(total / 60)分钟"
        }
        if total < 86_400 {
            return "\(total / 3_600)小时"
        }
        return "\(total / 86_400)天"
    }
}

extension Date {
    var relativeShort: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 {
            return "刚刚"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60)) 分钟前"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600)) 小时前"
        }
        return formatted(.dateTime.month().day().hour().minute())
    }

    var clockTime: String {
        formatted(.dateTime.hour().minute())
    }
}
