import Foundation

// MARK: - 检索包数据结构（对应 serve.py 返回）

struct Chunk: Codable {
    let idx: Int
    let file: String
    let title: String
    let section: String
    let text: String
    let url: String
    let score: Double
    let bm25_rank: Int?
    let vec_rank: Int?
}

struct SkillBundle: Codable {
    let skill: String
    let level: String
    let evidence: String
    let query: String
    let chunks: [Chunk]
}

struct RetrieveResponse: Codable {
    let ok: Bool
    let bundle: [SkillBundle]?
    let error: String?
}

enum RAGError: LocalizedError {
    case notRunning
    case spawnFailed(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "检索进程未启动。"
        case .spawnFailed(let s): return "启动内嵌检索进程失败：\(s)"
        case .badResponse(let s): return "检索进程返回异常：\(s)"
        }
    }
}

// MARK: - 内嵌检索进程桥接

final class RAGBridge {
    static let shared = RAGBridge()

    private var process: Process?
    private var inputPipe: Pipe?
    private var buffer = Data()
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private let queue = DispatchQueue(label: "ragbridge")

    var isRunning: Bool { process?.isRunning == true }

    // MARK: 路径解析：环境变量 > App 内嵌 > 开发硬编码

    private var serverPath: String {
        ProcessInfo.processInfo.environment["RAG_SERVER_PATH"]
            ?? Bundle.main.url(forResource: "rag_server", withExtension: nil, subdirectory: "rag")?.path
            ?? "/Users/guozhuangzhuang02/baidu/lora/interview_app/dist/rag_server/rag_server"
    }
    private var dataDir: String {
        ProcessInfo.processInfo.environment["RAG_DATA_DIR"]
            ?? Bundle.main.resourceURL?.appendingPathComponent("rag/data").path
            ?? "/Users/guozhuangzhuang02/baidu/lora/interview_app/data"
    }
    private var cacheDir: String {
        ProcessInfo.processInfo.environment["RAG_CACHE_DIR"]
            ?? Bundle.main.resourceURL?.appendingPathComponent("rag/models").path
            ?? "/Users/guozhuangzhuang02/baidu/lora/interview_app/dist/models"
    }

    func start() throws {
        if isRunning { return }
        let server = serverPath
        guard FileManager.default.fileExists(atPath: server) else {
            throw RAGError.spawnFailed("找不到 rag_server 可执行文件：\(server)")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: server)
        var env = ProcessInfo.processInfo.environment
        env["RAG_DATA_DIR"] = dataDir
        env["RAG_CACHE_DIR"] = cacheDir
        p.environment = env

        let input = Pipe()
        let output = Pipe()
        let err = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = err

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleRead(handle)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                print("[rag_server]", s)
            }
        }

        try p.run()
        process = p
        inputPipe = input
    }

    func stop() {
        process?.terminate()
        process = nil
        inputPipe = nil
        buffer.removeAll()
        for w in waiters { w.resume(throwing: RAGError.notRunning) }
        waiters.removeAll()
    }

    private func handleRead(_ handle: FileHandle) {
        let data = handle.availableData
        if data.isEmpty { return }
        queue.sync {
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<nl])
                buffer.removeSubrange(buffer.startIndex...nl)
                if let w = waiters.first {
                    waiters.removeFirst()
                    w.resume(returning: line)
                }
            }
        }
    }

    private func send(_ data: Data) async throws -> Data {
        guard let inputPipe else { throw RAGError.notRunning }
        var line = data
        line.append(0x0A)
        queue.sync { inputPipe.fileHandleForWriting.write(line) }
        return try await withCheckedThrowingContinuation { cont in
            queue.sync { waiters.append(cont) }
        }
    }

    private struct RetrieveRequest: Codable {
        let action: String
        let resume: ResumeData
    }

    /// 检索：简历技能点 -> 每技能点 top 片段
    func retrieve(resume: ResumeData) async throws -> [SkillBundle] {
        if !isRunning { try start() }
        let req = RetrieveRequest(action: "retrieve", resume: resume)
        let data = try JSONEncoder().encode(req)
        let respData = try await send(data)
        let resp = try JSONDecoder().decode(RetrieveResponse.self, from: respData)
        if !resp.ok { throw RAGError.badResponse(resp.error ?? "未知错误") }
        return resp.bundle ?? []
    }

    /// 把检索包格式化成给 LLM 的文本（四层出处）
    static func formatBundle(_ bundles: [SkillBundle]) -> String {
        var lines: [String] = []
        for b in bundles {
            lines.append("## 技能点：\(b.skill)（\(b.level)）")
            lines.append("查询：\(b.query)")
            lines.append("")
            if b.chunks.isEmpty {
                lines.append("（无召回片段）")
                lines.append("")
                continue
            }
            for (i, c) in b.chunks.enumerated() {
                lines.append("### [\(i + 1)] \(c.title)")
                lines.append("- 文件：\(c.file)")
                lines.append("- 章节：\(c.section)")
                lines.append("- 链接：\(c.url)")
                lines.append("- 原文：\(c.text)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
