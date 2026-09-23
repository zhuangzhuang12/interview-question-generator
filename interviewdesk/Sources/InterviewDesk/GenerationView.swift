import SwiftUI

/// 生成：检索 → LLM 生成题卷初稿 → 展示 → 写入当前面试。
struct GenerationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: InterviewStore
    @Environment(\.dismiss) private var dismiss

    let resume: ResumeData

    enum Stage { case retrieving, generating, done }
    @State private var stage: Stage = .retrieving
    @State private var questions: [InterviewQuestion] = []
    @State private var errorMessage: String?
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 760, height: 640)
        .task { await run() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("生成面试题卷")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("候选人：\(resume.name) · \(resume.skills.count) 个技能点")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(22)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .retrieving:
            statusView(icon: "magnifyingglass", text: "正在检索语料（BM25 + 向量，RRF 融合）…")
        case .generating:
            statusView(icon: "sparkles", text: "正在让 LLM 生成题卷初稿…")
        case .done:
            if errorMessage != nil {
                errorView
            } else {
                resultView
            }
        }
    }

    private func statusView(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Label(text, systemImage: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(errorMessage ?? "发生未知错误")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("重试") {
                errorMessage = nil
                Task { await run() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(questions) { q in
                        resultRow(q)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("已生成 \(questions.count) 道题，可写入当前面试后逐题校对。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("写入当前面试") { writeAll() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }

    private func resultRow(_ q: InterviewQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(q.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(q.category)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentBlue.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(q.prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !q.keyPoints.isEmpty {
                Label(q.keyPoints, systemImage: "scope")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(2)
            }
            if !q.source.isEmpty {
                Label(sourceSummary(q.source), systemImage: "link.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
    }

    private func sourceSummary(_ source: String) -> String {
        let firstLine = source.components(separatedBy: .newlines).first ?? ""
        return firstLine
    }

    private func writeAll() {
        store.replaceQuestions(questions)
        dismiss()
    }

    private func run() async {
        do {
            stage = .retrieving
            let bundles = try await RAGBridge.shared.retrieve(resume: resume)
            stage = .generating
            let bundleText = RAGBridge.formatBundle(bundles)
            let client = LLMClient(settings: settings.settings)
            let qs = try await client.generateQuestions(resume: resume, bundleText: bundleText)
            await MainActor.run {
                questions = qs
                stage = .done
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}
