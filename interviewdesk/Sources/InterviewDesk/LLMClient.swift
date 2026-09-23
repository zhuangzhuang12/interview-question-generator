import Foundation
import SwiftUI

// MARK: - 设置（LLM 配置，UserDefaults 持久化）

struct LLMSettings: Codable {
    var baseURL: String = "https://api.openai.com/v1"
    var apiKey: String = ""
    var model: String = "gpt-4o"
}

final class SettingsStore: ObservableObject {
    @Published var settings: LLMSettings {
        didSet { save() }
    }
    private let key = "llmSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(LLMSettings.self, from: data) {
            settings = s
        } else {
            settings = LLMSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 数据结构（简历结构化结果）

struct ResumeSkill: Codable, Identifiable, Hashable {
    var name: String
    var level: String
    var evidence: String
    var id: String { name }
}

struct ResumeData: Codable {
    var name: String = ""
    var skills: [ResumeSkill] = []
}

// MARK: - LLM 客户端（OpenAI 兼容 chat/completions）

enum LLMError: LocalizedError {
    case noAPIKey
    case network(String)
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "未配置 API Key，请在「设置」里填写。"
        case .network(let s): return "接口调用失败：\(s)"
        case .badJSON(let s): return "解析模型返回的 JSON 失败：\(s)"
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let response_format: [String: String]?
}

private struct ChatResponse: Codable {
    struct Choice: Codable { let message: ChatMessage }
    let choices: [Choice]
}

struct LLMClient {
    let settings: LLMSettings

    /// 基础 chat 调用，jsonMode 时要求模型只返回 JSON。
    func chat(messages: [ChatMessage], jsonMode: Bool) async throws -> String {
        guard !settings.apiKey.isEmpty else { throw LLMError.noAPIKey }
        let base = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else {
            throw LLMError.network("baseURL 非法")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(model: settings.model, messages: messages,
                               response_format: jsonMode ? ["type": "json_object"] : nil)
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw LLMError.network(msg)
        }
        let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = parsed.choices.first?.message.content else {
            throw LLMError.network("模型无返回内容")
        }
        return content
    }

    /// 从 LLM 返回文本里抽取 JSON（容忍 ```json 包裹与前后杂字）。
    static func extractJSON(from text: String) throws -> Data {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            var lines = s.components(separatedBy: "\n")
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.hasPrefix("```") == true { lines.removeLast() }
            s = lines.joined(separator: "\n")
        }
        if let start = s.range(of: "{"),
           let end = s.range(of: "}", options: .backwards) {
            s = String(s[start.lowerBound...end.lowerBound])
        }
        guard let data = s.data(using: .utf8) else { throw LLMError.badJSON("编码失败") }
        return data
    }

    // MARK: 业务方法一：简历文本 -> 技能点

    func structResume(from text: String) async throws -> ResumeData {
        let sys = ChatMessage(role: "system", content: """
你是一名简历解析助手。从用户提供的简历文本中抽取候选人的技能点，用于后续技术面试出题。

只输出 JSON，不要任何解释文字。JSON 结构：
{
  "name": "候选人姓名（中文；无则用「候选人」）",
  "skills": [
    {
      "name": "技能点名称，如「RAG / GraphRAG」「Redis」「消息队列 / Flink」",
      "level": "熟练度：精通/熟练/熟悉/了解（从简历措辞推断）",
      "evidence": "空格分隔的检索关键词，挑选最能代表该技能、且适合去技术语料里检索的具体词，如「分布式锁 看门狗 自动续期」「多跳推理 知识图谱 混合检索」"
    }
  ]
}
要求：聚焦可考察的技术栈（后端/中间件/算法/框架），给 3~5 个技能点；evidence 每项 3~8 个词。
""")
        let user = ChatMessage(role: "user", content: text)
        let raw = try await chat(messages: [sys, user], jsonMode: true)
        let data = try Self.extractJSON(from: raw)
        return try JSONDecoder().decode(ResumeData.self, from: data)
    }

    // MARK: 业务方法二：检索包 -> 题卷初稿

    func generateQuestions(resume: ResumeData, bundleText: String) async throws -> [InterviewQuestion] {
        let sys = ChatMessage(role: "system", content: """
你是一名资深技术面试官。根据候选人的简历技能点和给定的语料检索片段，生成一份面试题卷，只输出 JSON。
""")
        let user = ChatMessage(role: "user", content: """
候选人技能点：
\(resume.skills.map { "- \($0.name)（\($0.level)）：\($0.evidence)" }.joined(separator: "\n"))

语料检索片段（每个技能点的 top 片段，含四层出处）：
\(bundleText)

请按以下要求生成题卷，输出 JSON：
{
  "questions": [
    {
      "category": "分类（用技能点名称）",
      "id": "唯一英文短标识",
      "title": "N · 题目标题",
      "prompt": "面试问题（结合候选人项目，非纯八股）",
      "answerPoints": ["【标题】答案要点，锚定片段"],
      "keyPoints": "考察点：一句话说明这题考察什么能力",
      "source": "出处四层：文件名 → 章节 → 原文 → 链接；未覆盖标 ⚠️ 语料外",
      "followUps": ["追问1", "追问2"]
    }
  ]
}

硬约束：
1. 为每个技能点出 2~4 道题，总计 8~12 道；熟练度「精通」出深挖细节+追问，低熟练度出基础+边界。
2. 答案必须锚定给定片段，禁止编造片段没有的内容。
3. source 严格四层「文件名 → 章节 → 原文 → 链接」；片段未覆盖的知识点必须标「⚠️ 语料外」。
4. 只输出 JSON，不要任何解释或 markdown 包裹。
""")
        let raw = try await chat(messages: [sys, user], jsonMode: true)
        let data = try Self.extractJSON(from: raw)
        struct Wrapper: Codable { let questions: [InterviewQuestion] }
        return try JSONDecoder().decode(Wrapper.self, from: data).questions
    }
}
