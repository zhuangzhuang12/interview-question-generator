import SwiftUI

@main
struct InterviewDeskApp: App {
    @StateObject private var store = InterviewStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建面试记录") { store.resetInterview() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

struct InterviewQuestion: Identifiable, Codable, Hashable {
    var id: String
    var category: String
    var title: String
    var prompt: String
    var answerPoints: [String]
    var keyPoints: String = ""
    var source: String = ""
    var followUps: [String]
}

struct QuestionRecord: Codable {
    var done = false
    var rating = 0
    var notes = ""
}

struct InterviewSnapshot: Codable {
    var questions: [InterviewQuestion]? = nil
    var contentVersion: Int? = nil
    var records: [String: QuestionRecord]
    var overallNote = ""
    var recommendation = "待定"
    var candidateSignal = ""
    var risk = ""
}

final class InterviewStore: ObservableObject {
    @Published var questions = InterviewData.questions
    @Published var selectedID: String? = InterviewData.questions.first?.id
    @Published var records: [String: QuestionRecord] = [:]
    @Published var overallNote = ""
    @Published var recommendation = "待定"
    @Published var candidateSignal = ""
    @Published var risk = ""

    private let saveURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent("InterviewDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        saveURL = folder.appendingPathComponent("interview.json")
        load()
    }

    var selectedQuestion: InterviewQuestion? {
        questions.first { $0.id == selectedID }
    }

    var completedCount: Int {
        questions.filter { records[$0.id]?.done == true }.count
    }

    var progress: Double {
        questions.isEmpty ? 0 : Double(completedCount) / Double(questions.count)
    }

    func record(for question: InterviewQuestion) -> QuestionRecord {
        records[question.id] ?? QuestionRecord()
    }

    func update(_ record: QuestionRecord, for question: InterviewQuestion) {
        records[question.id] = record
        save()
    }

    func save() {
        let snapshot = InterviewSnapshot(questions: questions, contentVersion: 3, records: records, overallNote: overallNote,
                                         recommendation: recommendation, candidateSignal: candidateSignal, risk: risk)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let snapshot = try? JSONDecoder().decode(InterviewSnapshot.self, from: data) else { return }
        if let savedQuestions = snapshot.questions, !savedQuestions.isEmpty {
            if (snapshot.contentVersion ?? 1) < 2 {
                questions = InterviewData.migratedQuestions(from: savedQuestions)
            } else {
                questions = savedQuestions
            }
            selectedID = questions.first?.id
        }
        records = snapshot.records
        overallNote = snapshot.overallNote
        recommendation = snapshot.recommendation
        candidateSignal = snapshot.candidateSignal
        risk = snapshot.risk
    }

    func resetInterview() {
        records = [:]
        overallNote = ""
        recommendation = "待定"
        candidateSignal = ""
        risk = ""
        selectedID = questions.first?.id
        save()
    }

    func upsertQuestion(_ question: InterviewQuestion) {
        if let index = questions.firstIndex(where: { $0.id == question.id }) {
            questions[index] = question
        } else {
            questions.append(question)
        }
        selectedID = question.id
        save()
    }

    func deleteQuestion(_ question: InterviewQuestion) {
        questions.removeAll { $0.id == question.id }
        records.removeValue(forKey: question.id)
        selectedID = questions.first?.id
        save()
    }

    func replaceQuestions(_ newQuestions: [InterviewQuestion]) {
        questions = newQuestions
        let ids = Set(newQuestions.map(\.id))
        records = records.filter { ids.contains($0.key) }
        selectedID = newQuestions.first?.id
        save()
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: InterviewStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var search = ""
    @State private var showAnswers = true
    @State private var showingResetAlert = false
    @State private var showingQuestionEditor = false
    @State private var showingSettings = false
    @State private var showingFlow = false
    @State private var flowResume: ResumeData?
    @State private var editorQuestion = InterviewData.blankQuestion()

    private var filteredQuestions: [InterviewQuestion] {
        guard !search.isEmpty else { return store.questions }
        return store.questions.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.prompt.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    private var groups: [(String, [InterviewQuestion])] {
        let grouped = Dictionary(grouping: filteredQuestions, by: \ .category)
        var categoryOrder = InterviewData.categories
        for category in filteredQuestions.map(\.category) where !categoryOrder.contains(category) {
            categoryOrder.append(category)
        }
        return categoryOrder.compactMap { category in
            guard let values = grouped[category], !values.isEmpty else { return nil }
            return (category, values)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .background(Color.appBackground)
        .alert("清空当前面试记录？", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.resetInterview() }
        } message: {
            Text("问题库不会删除，只会清空评分、完成状态和面试笔记。")
        }
        .sheet(isPresented: $showingQuestionEditor) {
            QuestionEditor(question: $editorQuestion) {
                store.upsertQuestion(editorQuestion)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingFlow) {
            if let resume = flowResume {
                GenerationView(resume: resume)
            } else {
                ResumeImportView { resume in
                    flowResume = resume
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentBlue)
                    Text("Interview Desk")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        editorQuestion = InterviewData.blankQuestion()
                        showingQuestionEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.accentBlue)
                            .frame(width: 26, height: 26)
                            .background(Color.accentBlue.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("添加面试问题")
                }
                Text("候选人 · 校招 · 后端开发工程师（SWE 平台组）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索问题", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(9)
            .background(Color.white.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Button {
                flowResume = nil
                showingFlow = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                    Text("导入简历 · 生成题卷")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Color.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .shadow(color: Color.accentBlue.opacity(0.35), radius: 4, y: 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                    Text("LLM 设置")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.accentBlue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.accentBlue.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Button {
                store.selectedID = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .foregroundStyle(Color.accentGreen)
                    Text("面试总结")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(store.selectedID == nil ? Color.accentGreen.opacity(0.12) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    ForEach(groups, id: \.0) { category, questions in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)

                            ForEach(questions) { question in
                                QuestionRow(question: question,
                                            record: store.record(for: question),
                                            isSelected: store.selectedID == question.id) {
                                    store.selectedID = question.id
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 18)
            }

            Divider()
            HStack(spacing: 10) {
                ProgressView(value: store.progress)
                    .tint(Color.accentBlue)
                Text("\(store.completedCount)/\(store.questions.count) 已完成")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(16)
        }
        .frame(width: 285)
        .background(Color.sidebarBackground)
    }

    @ViewBuilder
    private var detail: some View {
        if let question = store.selectedQuestion {
            QuestionDetail(question: question, showAnswers: $showAnswers)
        } else {
            SummaryView()
        }
    }
}

struct QuestionRow: View {
    let question: InterviewQuestion
    let record: QuestionRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: record.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(record.done ? Color.accentGreen : .secondary.opacity(0.55))
                VStack(alignment: .leading, spacing: 3) {
                    Text(question.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(question.category)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentBlue.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct QuestionDetail: View {
    @EnvironmentObject private var store: InterviewStore
    @Environment(\.dismiss) private var dismiss
    let question: InterviewQuestion
    @Binding var showAnswers: Bool
    @State private var record = QuestionRecord()
    @State private var draftQuestion: InterviewQuestion
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false

    init(question: InterviewQuestion, showAnswers: Binding<Bool>) {
        self.question = question
        self._showAnswers = showAnswers
        self._draftQuestion = State(initialValue: question)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().padding(.top, 25)
                promptCard
                if showAnswers {
                    answerCard
                    if !question.keyPoints.isEmpty { keyPointsCard }
                    if !question.source.isEmpty { sourceCard }
                }
                recordCard
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 52)
            .padding(.vertical, 34)
        }
        .onAppear { record = store.record(for: question) }
        .onChange(of: question.id) { _, _ in
            record = store.record(for: question)
            draftQuestion = question
        }
        .onChange(of: record.done) { _, _ in persist() }
        .onChange(of: record.rating) { _, _ in persist() }
        .onChange(of: record.notes) { _, _ in persist() }
        .sheet(isPresented: $showingEditor) {
            QuestionEditor(question: $draftQuestion) {
                store.upsertQuestion(draftQuestion)
            }
        }
        .alert("删除这道面试题？", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteQuestion(question)
            }
        } message: {
            Text("删除后，该题的评分和面试笔记也会一并删除。")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    draftQuestion = question
                    showingEditor = true
                } label: {
                    Label("编辑问题", systemImage: "pencil")
                }
                Button {
                    showingDeleteAlert = true
                } label: {
                    Label("删除问题", systemImage: "trash")
                }
                .tint(.red)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(showAnswers ? "隐藏参考答案" : "显示参考答案") { showAnswers.toggle() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(question.category.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Text("问题 \(questionNumber)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(question.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                Tag(text: "建议 3-5 分钟", color: .accentOrange)
                Tag(text: record.done ? "已完成" : "进行中", color: record.done ? .accentGreen : .accentBlue)
            }
        }
    }

    private var questionNumber: Int {
        guard let index = store.questions.firstIndex(of: question) else { return 0 }
        return index + 1
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("面试问题", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentBlue)
            Text(question.prompt)
                .font(.system(size: 17, weight: .medium))
                .lineSpacing(5)
                .foregroundStyle(Color.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blueWash)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 23)
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("标准答案要点", systemImage: "lightbulb.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentOrange)
            ForEach(Array(question.answerPoints.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 10) {
                    Text("0\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentOrange)
                        .frame(width: 24, height: 24)
                        .background(Color.orangeWash)
                        .clipShape(Circle())
                    Text(point)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
        .padding(.top, 16)
    }

    private var keyPointsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("考察点", systemImage: "scope")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentBlue)
            Text(question.keyPoints)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Color.ink)
        }
        .padding(20)
        .background(Color.blueWash)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 16)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("出处", systemImage: "link.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentGreen)
            Text(sourceText)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Color.ink)
            if let url = sourceLink {
                Link(destination: url) {
                    Label("打开原文链接", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .padding(20)
        .background(Color.greenWash)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 16)
    }

    /// 出处正文（去掉「链接：」行，链接单独用 Link 展示）
    private var sourceText: String {
        question.source.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("链接") }
            .joined(separator: "\n")
    }

    /// 从出处里提取原文链接（「链接：」行优先，否则扫 http 开头的 token）
    private var sourceLink: URL? {
        for line in question.source.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("链接") {
                if let r = t.range(of: "https?://") {
                    return URL(string: String(t[r.lowerBound...]))
                }
            }
        }
        return nil
    }

    private var recordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("面试记录", systemImage: "pencil.and.list.clipboard")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentGreen)
                Spacer()
                Toggle("已问完", isOn: $record.done)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("表现评分")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    ForEach(1...5, id: \.self) { score in
                        Button {
                            record.rating = score
                        } label: {
                            Image(systemName: score <= record.rating ? "star.fill" : "star")
                                .font(.system(size: 19))
                                .foregroundStyle(score <= record.rating ? Color.accentOrange : .secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(record.rating == 0 ? "未评分" : "\(record.rating)/5")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            TextEditor(text: $record.notes)
                .font(.system(size: 14))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    if record.notes.isEmpty {
                        Text("记录候选人的具体回答、亮点、疑点和追问结果…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            if !question.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("可选追问")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(question.followUps, id: \.self) { followUp in
                        Text("• \(followUp)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.greenWash)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 16)
    }

    private func persist() {
        store.update(record, for: question)
    }
}

struct QuestionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var question: InterviewQuestion
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.title.isEmpty ? "新增面试问题" : "编辑面试问题")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("题目内容、标准答案和追问都可以在这里维护")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("保存") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
            Divider()

            Form {
                Section("基本信息") {
                    TextField("分类，例如：后端基础", text: $question.category)
                    TextField("问题标题", text: $question.title)
                    TextEditor(text: $question.prompt)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if question.prompt.isEmpty {
                                Text("面试时向候选人提出的问题…")
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    ForEach(question.answerPoints.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1)")
                                .foregroundStyle(Color.accentOrange)
                                .frame(width: 22)
                            TextField("标准答案要点", text: $question.answerPoints[index])
                            Button {
                                question.answerPoints.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        question.answerPoints.append("")
                    } label: {
                        Label("添加答案要点", systemImage: "plus.circle")
                    }
                } header: {
                    Text("标准答案要点")
                }

                Section {
                    TextEditor(text: $question.keyPoints)
                        .frame(minHeight: 56)
                        .overlay(alignment: .topLeading) {
                            if question.keyPoints.isEmpty {
                                Text("这题考察候选人的哪些能力点…")
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("考察点")
                }

                Section {
                    TextEditor(text: $question.source)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if question.source.isEmpty {
                                Text("出处：文件名 → 章节 → 原文 → 链接（四层），语料未覆盖标 ⚠️ 语料外…")
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("出处")
                }

                Section {
                    ForEach(question.followUps.indices, id: \.self) { index in
                        HStack {
                            TextField("可选追问", text: $question.followUps[index])
                            Button {
                                question.followUps.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        question.followUps.append("")
                    } label: {
                        Label("添加追问", systemImage: "plus.circle")
                    }
                } header: {
                    Text("可选追问")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 620)
    }
}

struct SummaryView: View {
    @EnvironmentObject private var store: InterviewStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("面试总结")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("在这里收口，方便面试结束后快速判断是否进入下一轮。")
                    .foregroundStyle(.secondary)
                SummaryEditor(title: "整体表现", placeholder: "候选人的总体表现、沟通方式、学习能力…", text: $store.overallNote)
                SummaryEditor(title: "亮点信号", placeholder: "哪些回答体现了真实项目深度？", text: $store.candidateSignal)
                SummaryEditor(title: "风险与待验证点", placeholder: "哪些内容需要下一轮继续核验？", text: $store.risk)
                VStack(alignment: .leading, spacing: 10) {
                    Text("面试结论")
                        .font(.system(size: 13, weight: .bold))
                    Picker("面试结论", selection: $store.recommendation) {
                        Text("待定").tag("待定")
                        Text("强推荐").tag("强推荐")
                        Text("推荐但需验证").tag("推荐但需验证")
                        Text("谨慎").tag("谨慎")
                        Text("不推荐").tag("不推荐")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(18)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(52)
        }
        .onChange(of: store.overallNote) { _, _ in store.save() }
        .onChange(of: store.candidateSignal) { _, _ in store.save() }
        .onChange(of: store.risk) { _, _ in store.save() }
        .onChange(of: store.recommendation) { _, _ in store.save() }
    }
}

struct SummaryEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            TextEditor(text: $text)
                .font(.system(size: 14))
                .frame(minHeight: 95)
                .padding(8)
                .background(Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

extension Color {
    static let accentBlue = Color(red: 0.09, green: 0.35, blue: 0.59)
    static let accentGreen = Color(red: 0.12, green: 0.51, blue: 0.38)
    static let accentOrange = Color(red: 0.82, green: 0.39, blue: 0.10)
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.17)
    static let appBackground = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let sidebarBackground = Color(red: 0.93, green: 0.94, blue: 0.92)
    static let blueWash = Color(red: 0.88, green: 0.93, blue: 0.97)
    static let orangeWash = Color(red: 0.99, green: 0.93, blue: 0.84)
    static let greenWash = Color(red: 0.89, green: 0.95, blue: 0.91)
    static let paper = Color.white.opacity(0.82)
}

enum InterviewData {
    static let categories = ["经历与动机", "大厂实习", "Agent 与 RAG", "后端基础", "科研与编程", "综合判断"]

    static func blankQuestion() -> InterviewQuestion {
        InterviewQuestion(id: UUID().uuidString, category: "后端基础", title: "新面试问题", prompt: "",
                          answerPoints: [""], followUps: [])
    }

    static func migratedQuestions(from saved: [InterviewQuestion]) -> [InterviewQuestion] {
        let builtInByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        let custom = saved.filter { builtInByID[$0.id] == nil }
        return questions + custom
    }

    static let questions: [InterviewQuestion] = [
        InterviewQuestion(id: "intro-mainline", category: "经历与动机", title: "1 · 经历主线与平台后端动机", prompt: "请用 1 分钟介绍自己，并说明为什么申请 SWE 平台组后端开发。", answerPoints: [
            "主线应覆盖本硕学历、大厂后端实习、Agent/RAG 项目与 图检索论文研究。",
            "能把 AI 能力落到稳定、可观测、可评测的平台工程，而不只停留在模型调用。",
            "明确个人主导、独立实现和团队协作边界，并能给出代码或指标证据。"
        ], followUps: ["简历中哪一项最能代表你的后端能力？", "为什么不是纯算法岗？", "入职后三个月最想补齐什么？"]),

        InterviewQuestion(id: "push-realtime", category: "大厂实习", title: "2 · Push 实时链路扩容限流", prompt: "请画出实时 Push 链路，并解释“独立扩容限流器 + 重点人群兜底”的设计、容量依据和故障边界。", answerPoints: [
            "说明入口、消费、召排、限流、投放及监控位置，区分业务限额与系统保护限流。",
            "限流算法、Key 粒度、配置下发、并发安全、热 Key 与降级策略应自洽。",
            "能解释曝光 PV、交易订单 的实验口径、对照组、周期和因果归因。"
        ], followUps: ["限流器实例扩缩容时额度如何保持准确？", "Redis 或配置中心故障怎么办？", "提升为什么能归因于你的方案？"]),

        InterviewQuestion(id: "push-offline", category: "大厂实习", title: "3 · 离线失败恢复与幂等", prompt: "离线 Push 失败后，Flink、Mafka、Redis 时段缓存和分布式锁如何协作恢复？请按消息状态机说明。", answerPoints: [
            "失败事件应包含幂等键、单元、时段、失败原因和版本；Flink 消费后判断是否可恢复。",
            "恢复 Redis 缓存需处理重复、乱序、迟到和消息重放；原子性不能只依赖一个模糊的分布式锁描述。",
            "说明锁粒度、TTL、持锁失败、业务执行超时、解锁校验，以及最终补偿和告警。"
        ], followUps: ["加锁成功后进程宕机怎么办？", "同一单元失败事件重复 3 次会怎样？", "为什么不用 Lua、事务或幂等状态表？"]),

        InterviewQuestion(id: "kb-agent", category: "Agent 与 RAG", title: "4 · 自进化知识库与代码图谱", prompt: "平台工单 Agent 的知识库如何增量同步、判断知识成熟度，并用命中反馈驱动更新？GitNexus 代码图谱在链路中的作用是什么？", answerPoints: [
            "讲清文档/工单采集、切分、去重、版本、索引更新与回滚，避免过期和冲突知识污染。",
            "成熟度需要可计算信号，如来源可信度、人工确认、命中后解决率、时效和冲突状态。",
            "代码图谱应说明实体/边、仓库版本绑定、权限隔离、检索融合及失效更新。"
        ], followUps: ["错误答案被正反馈会不会越学越错？", "代码更新后旧图谱如何淘汰？", "权限不同的用户如何避免越权检索？"]),

        InterviewQuestion(id: "agent-eval", category: "Agent 与 RAG", title: "5 · Skill 调用与多轮评测", prompt: "你开发的查询/转换类 Skill 如何定义契约、校验参数和处理失败？多轮评测集如何证明 Agent 真的变好？", answerPoints: [
            "Skill 需有结构化输入输出、权限、超时、重试、幂等、错误类型和可观测 trace。",
            "评测覆盖意图识别、参数抽取、工具选择、调用成功率、最终解决率及多轮状态保持。",
            "数据集应防泄漏、分难度并保留回归集；区分离线自动指标、LLM 裁判和人工验收。"
        ], followUps: ["工具返回部分成功时如何生成答案？", "如何避免评测被 Prompt 记住？", "一个失败 Case 如何定位到具体节点？"]),

        InterviewQuestion(id: "personal-agent", category: "Agent 与 RAG", title: "6 · LangGraph 个人 Agent 项目", prompt: "Planner-Actor-Reflector-Adjuster 为什么需要四阶段？AgentState、短长期记忆和混合检索如何设计？", answerPoints: [
            "能给出状态字段、节点转移、循环终止、失败恢复和持久化，而非只复述框架名。",
            "Redis 与 Qdrant 的职责边界、记忆写入/召回策略、用户隔离和过期删除应明确。",
            "向量 + BM25 融合需说明召回、归一化/重排、TopK、引用与健康建议安全边界。"
        ], followUps: ["Reflector 误判会导致什么？", "多轮并发请求如何避免状态覆盖？", "专业性提升如何量化？"]),

        InterviewQuestion(id: "similarity-memory", category: "后端基础", title: "7 · 文案相似度与内存优化", prompt: "为什么 MD5 不适合相似文案识别？Levenshtein 方案怎样控制复杂度、阈值和误杀？布隆过滤器迁移为何能释放 400+ MB？", answerPoints: [
            "MD5 只能判断精确相等；编辑距离要做归一化、长度预过滤、分桶或候选召回，避免全量 O(nm) 比较。",
            "拦截率从 0.0025% 到 3.05% 不是质量结论，还需准确率、召回率、误杀率和人工样本验证。",
            "BloomFilter 内存应能由 n、误判率 p 和哈希数 k 推导；说明迁移前后位置、容量和性能代价。"
        ], followUps: ["中文同义改写编辑距离很大怎么办？", "阈值如何按业务成本确定？", "400 MB 的测量方法是什么？"]),

        InterviewQuestion(id: "backend-core", category: "后端基础", title: "8 · MySQL、Redis、Kafka 与 Java", prompt: "结合实习链路，选一个具体写请求说明事务、索引、缓存和消息如何配合；再说明 Java 并发与 JVM 风险。", answerPoints: [
            "MySQL 能讲索引、执行计划、事务隔离、锁与幂等唯一键；Redis 明确缓存一致性和热 Key 风险。",
            "Kafka/Mafka 需说明分区、有序、重复消费、至少一次语义、积压与重试/死信。",
            "Java 能覆盖线程池参数、异常处理、锁/CAS、内存模型及 OOM/GC 排查。"
        ], followUps: ["消息已消费但数据库提交失败怎么办？", "缓存删除失败如何补偿？", "线程池队列满时选什么拒绝策略？"]),

        InterviewQuestion(id: "distributed-lock", category: "后端基础", title: "9 · 分布式锁正确性", prompt: "请设计一个用于恢复 Redis 时段缓存的分布式锁，并说明它在哪些条件下仍可能失效。", answerPoints: [
            "使用唯一 owner token、SET NX PX 与校验 owner 后删除；业务时长不确定时需续租或 fencing token。",
            "讨论超时后旧持有者继续执行、主从切换、网络暂停、时钟和锁粒度问题。",
            "锁不是幂等替代品；最终仍需业务状态、版本号或唯一约束兜底。"
        ], followUps: ["Redlock 能完全解决吗？", "如何防止误删别人的锁？", "不用锁能否实现？"]),

        InterviewQuestion(id: "rag-paper", category: "科研与编程", title: "10 · 图检索论文深挖", prompt: "请从问题定义、核心方法、实验与失败案例介绍 图检索论文，并解释它如何缓解多跳检索漂移。", answerPoints: [
            "规划引导任务分解、意图锚点、类型约束扩展和图融合之间应有清晰数据流与创新点。",
            "能说明数据集、强基线、消融、统计显著性、成本/时延，以及与 GraphRAG/某开源图检索框架的差异。",
            "应能回答关键实现、负例和局限，而不只讲摘要。"
        ], followUps: ["最关键的消融结果是什么？", "哪类问题反而退化？", "如果去掉类型约束会发生什么？"]),

        InterviewQuestion(id: "coding", category: "科研与编程", title: "11 · 编程题：并发安全限流器", prompt: "用 Java 实现一个线程安全的令牌桶限流器：支持每秒补充 rate 个令牌、容量 capacity、tryAcquire(n)，并说明测试方法。", answerPoints: [
            "基于单调时钟计算增量，令牌数不超过容量；补充与扣减必须原子，可用锁或 CAS。",
            "处理首次调用、长时间空闲、n 非法、浮点/整数精度、时钟回拨与高并发竞争。",
            "测试包含确定性时钟、容量上限、突发、稳定速率和多线程不超发；分析时间/空间复杂度。"
        ], followUps: ["分布式场景如何扩展？", "实例扩容如何避免总额度翻倍？", "滑动窗口与令牌桶的取舍？"]),

        InterviewQuestion(id: "verdict", category: "综合判断", title: "12 · 真实性与成长性判断", prompt: "从 Push 优化、Agent 平台、图检索论文中任选一项，给出你亲自做过的最难决策：备选方案、取舍、验证、上线和复盘。", answerPoints: [
            "优秀回答有具体约束、代码/数据证据和个人决策链，能区分团队成果与个人贡献。",
            "能主动指出方案局限、失败尝试、线上风险及下一步，而不是只报正向指标。",
            "综合观察学习速度、结构化沟通、工程严谨性与对业务指标的敏感度。"
        ], followUps: ["如果重做一次会改什么？", "让同事评价你的最大短板会是什么？", "哪项简历表述最容易被误解？"])
    ]
}
