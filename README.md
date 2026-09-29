# 智能面试出题系统（InterviewDesk）

RAG 驱动的面试出题工具：把候选人简历自动变成一份**带考察点、带四层出处、可校对的面试题卷**。

> 简历 → 检索语料 → LLM 生成题卷初稿 → App 内校对 → 落库

## 组成

| 目录 | 说明 | 技术栈 |
|------|------|--------|
| `interview_app/` | RAG 检索流水线（命令行 + 常驻检索服务） | Python、jieba + BM25、fastembed + onnxruntime |
| `interviewdesk/` | macOS 桌面 App（内嵌检索进程 + 生成编排） | SwiftUI、SPM、macOS 14+ |
| `面试出题系统-设计方案.md` | 整体设计文档 | — |
| `interview_app/docs/architecture.md` | 检索服务架构介绍 | — |

## 架构

```
PDF 简历
  → [PDFKit] 抽文本
  → [LLM] 结构化技能点 {name, level, evidence}
  → [内嵌 Python 检索] 检索包（每技能点 top-5 片段 + 四层出处）
  → [LLM] 题卷初稿 JSON（~10 题，含 keyPoints/source/followUps，⚠️ 语料外标记）
  → [App] 展示 + 逐题校对
  → InterviewStore.save() 落 interview.json（contentVersion 3）
```

**检索**采用双路召回 + RRF 融合：

- BM25（jieba 分词 + `rank_bm25`）top-20
- 向量（`bge-small-zh-v1.5` 512 维，fastembed/onnxruntime）top-20
- RRF（k=60）融合后取 top-5，每条片段带四层出处：**文件名 → 章节 → 原文 → 链接**

## 快速开始

### 1. Python 检索流水线（`interview_app/`）

```bash
cd interview_app
pip install -r requirements.txt

# 准备语料（语料与索引文件未随仓库分发，需本地生成）
python -m corpus.clean && python -m corpus.chunk && python -m corpus.index

# 命令行：简历 → 检索包
python main.py resume/sample_xxx.json

# 常驻检索服务（供 App 内嵌，stdin/stdout JSON-lines）
python serve.py
```

> `data/`（索引）、`dist/`（PyInstaller 打包产物）、`crazymakercircle_blog/`（语料源）体积大，已通过 `.gitignore` 排除，需本地生成。

### 2. macOS App（`interviewdesk/`）

```bash
cd interviewdesk
swift build                    # 开发调试
./build_app.sh                 # 编译 + 组装 .app + 内嵌 RAG + 签名
```

`build_app.sh` 会从 `interview_app/dist/rag_server` 与 `interview_app/data` 抽取检索运行时，内嵌进 `.app`，产出可分发的 `InterviewDesk.app`（签名 + 公证见脚本内注释）。

## App 内使用流程

1. 点 ⚙️「LLM 设置」，填 OpenAI 兼容接口（base_url / api_key / model）
2. 点「导入简历 · 生成题卷」→ 选 PDF 简历 → 确认技能点
3. 自动「检索 → 生成题卷初稿」→ 逐题校对 →「写入当前面试」

## 目录结构

```
.
├── interview_app/
│   ├── corpus/          # 语料清洗 / 分块 / 建索引
│   ├── retrieve/        # BM25 + 向量混合检索（RRF）
│   ├── resume/          # 简历解析
│   ├── generate/        # 题卷生成 prompt + 注入
│   ├── serve.py         # 常驻检索服务（App 内嵌）
│   └── docs/architecture.md
├── interviewdesk/
│   ├── Sources/InterviewDesk/   # SwiftUI 视图 + 桥接
│   ├── build_app.sh             # 打包脚本
│   └── Package.swift
├── 面试出题系统-设计方案.md
└── .gitignore
```
