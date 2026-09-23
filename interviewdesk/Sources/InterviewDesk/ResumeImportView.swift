import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// 简历导入：选 PDF → PDFKit 抽文本 → LLM 结构化 → 技能点确认。
struct ResumeImportView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    /// 技能点确认后回调（父视图据此进入生成阶段）
    var onConfirm: (ResumeData) -> Void

    @State private var showingFilePicker = false
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var resume: ResumeData?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let resume {
                confirmContent(resume)
            } else if isParsing {
                parsingContent
            } else {
                pickContent
            }
        }
        .frame(width: 660, height: 580)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            handlePicked(result)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("导入候选人简历")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("上传 PDF，自动解析出技能点用于出题")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(22)
    }

    private var pickContent: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentBlue)
            Text("拖入或选择一份 PDF 简历")
                .font(.system(size: 16, weight: .semibold))
            Text("解析由 LLM 完成：抽取姓名、技能点与熟练度、检索关键词。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                showingFilePicker = true
            } label: {
                Label("选择 PDF 文件", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private var parsingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("正在解析简历并抽取技能点…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func confirmContent(_ resume: ResumeData) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("候选人") {
                    TextField("姓名", text: Binding(
                        get: { self.resume?.name ?? "" },
                        set: { self.resume?.name = $0 }
                    ))
                }
                Section("技能点（确认或修改后用于出题）") {
                    ForEach(resume.skills.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("技能", text: Binding(
                                get: { resume.skills[index].name },
                                set: { self.resume?.skills[index].name = $0 }
                            ))
                            .frame(minWidth: 130)
                            Picker("", selection: Binding(
                                get: { resume.skills[index].level },
                                set: { self.resume?.skills[index].level = $0 }
                            )) {
                                ForEach(["精通", "熟练", "熟悉", "了解"], id: \.self) { Text($0) }
                            }
                            .labelsHidden()
                            .frame(width: 84)
                            TextField("检索关键词（空格分隔）", text: Binding(
                                get: { resume.skills[index].evidence },
                                set: { self.resume?.skills[index].evidence = $0 }
                            ))
                            Button {
                                self.resume?.skills.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        self.resume?.skills.append(ResumeSkill(name: "", level: "熟悉", evidence: ""))
                    } label: {
                        Label("添加技能点", systemImage: "plus.circle")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("重新选择") {
                    self.resume = nil
                    self.errorMessage = nil
                }
                Button("确认并生成题卷") {
                    onConfirm(resume)
                }
                .buttonStyle(.borderedProminent)
                .disabled(resume.skills.filter { !$0.name.isEmpty && !$0.evidence.isEmpty }.isEmpty)
            }
            .padding(20)
        }
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
            guard let doc = PDFDocument(url: url), let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "无法读取 PDF 或 PDF 内容为空。"
                return
            }
            parse(text)
        case .failure(let e):
            errorMessage = e.localizedDescription
        }
    }

    private func parse(_ text: String) {
        isParsing = true
        errorMessage = nil
        let client = LLMClient(settings: settings.settings)
        Task {
            do {
                let r = try await client.structResume(from: text)
                await MainActor.run {
                    resume = r
                    isParsing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isParsing = false
                }
            }
        }
    }
}
