# 智能面试出题 RAG 服务 — 架构介绍

> 一句话定位：把「手工写面试题」升级为可复用的检索增强流水线 —— 输入一份简历，从 698 篇技术语料检索相关片段，半自动生成结构化题卷，直接注入 macOS 面试应用 InterviewDesk。

---

## 1. 背景与目标

给一位候选人（如许昊洋）出面试题，传统做法是：人肉读简历 → 凭记忆翻技术文章 → 手写题目和答案 → 手抄进面试 App。换一位候选人就全流程重来，且答案出处靠记忆、容易失真。

本服务把它固化成 **RAG（检索增强生成）流水线**：

```
简历 ──► 检索（BM25 + 向量）──► 检索包 ──► Ducc 半自动生成题卷 ──► 注入 InterviewDesk
```

三项关键决策（已与需求方对齐）：

| 维度 | 选择 | 理由 |
|------|------|------|
| 范围 | 端到端 MVP | 先跑通简历→检索→生成→注入全链路 |
| 检索 | 混合检索（BM25 + 向量，RRF 融合） | 关键词精确匹配 + 语义召回互补 |
| 生成 | 半自动（Ducc 在会话里生成） | 答案质量与出处校验需要人把关，全自动易编造 |

---

## 2. 总体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        离线阶段（一次性）                          │
│                                                                 │
│  crazymakercircle_blog/                                          │
│   ├─ md/*.md   (698 篇技术博客)                                  │
│   └─ index.json (id/title/date/url/file 元数据)                  │
│          │                                                       │
│          ▼                                                       │
│  corpus/clean.py    行级清洗（去推广段/传送门/图片/公众号链接）      │
│          ▼                                                       │
│  corpus/chunk.py    按 ## 标题分块（500~800 字，带标题链+行号）    │
│          ▼                                                       │
│  corpus/index.py    jieba 分词 + fastembed 向量编码               │
│          │                                                       │
│          ├─ data/chunks.json  (28134 块 + tokens)                │
│          ├─ data/vectors.npy  (28134 × 512，已归一化)             │
│          └─ data/corpus.db    (SQLite，供人工查阅)                │
└─────────────────────────────────────────────────────────────────┘
                          │ 只读
┌─────────────────────────────────────────────────────────────────┐
│                        在线阶段（每次换候选人跑一遍）                │
│                                                                 │
│  resume/sample_xxx.json  ──► resume/parse.py  结构化技能点+子查询  │
│                                        │                         │
│                                        ▼                         │
│                              retrieve/search.py  混合检索          │
│                              (BM25 top20 + 向量 top20 → RRF → 5) │
│                                        │                         │
│                                        ▼                         │
│                              data/retrieval_bundle.{json,md}      │
│                                        │                         │
│                                        ▼  Ducc 阅读检索包          │
│                              generate/inject.py  生成题卷          │
│                                        │                         │
│                                        ▼                         │
│                     ~/Library/Application Support/InterviewDesk/  │
│                                  interview.json                  │
└─────────────────────────────────────────────────────────────────┘
```

数据流分两段：

- **离线段**：语料只清洗/分块/编码一次，产出 `chunks.json`、`vectors.npy`、`corpus.db` 三个索引产物，供后续反复检索。这是最耗时的一段（28134 块编码约 19 分钟），但只需跑一次。
- **在线段**：每次换候选人，只需「解析简历 → 混合检索 → 输出检索包 → 生成注入」，秒级到分钟级。

---

## 3. 目录结构

```
interview_app/
├── config.py                 # 全局路径 + 检索参数常量
├── main.py                   # 一键入口：简历 → 检索 → 输出检索包
├── requirements.txt          # jieba / rank-bm25 / fastembed / numpy
├── corpus/
│   ├── clean.py              # 行级清洗
│   ├── chunk.py              # 分块（四层出处）
│   └── index.py              # 建索引（BM25 tokens + 向量 + SQLite）
├── resume/
│   ├── parse.py              # 简历 JSON → 技能点 + 子查询
│   └── sample_xuhaoyang.json # 内置样例简历
├── retrieve/
│   └── search.py             # 混合检索 + RRF 融合
├── generate/
│   ├── build_prompt.py       # 检索包 → 可读 Markdown
│   └── inject.py             # 题卷生成 + 注入 InterviewDesk
└── data/                     # 运行时产物（索引 + 检索包）
    ├── chunks.json           # 28134 块 + tokens（131 MB）
    ├── vectors.npy           # 28134 × 512 向量（57 MB）
    ├── corpus.db            # SQLite chunks 表（48 MB）
    └── retrieval_bundle.{json,md}
```

---

## 4. 模块详解

### 4.1 `corpus/clean.py` — 行级清洗

目标：去掉 CSDN/公众号转载的技术文章里的噪音，保留技术正文与标题层级。逐行匹配，命中即删：

1. **元数据 blockquote**：`> 原文：…`、`> 日期：…`
2. **传送门/原文地址导航标题**：`本文原文地址传送门`、`原始的内容，请参考本文的原文地址`、`平台篇幅限制…` 及链接式变体 `[本文原文链接](…)`（正则 `_PORTAL_H`）
3. **公众号链接行**：`mp.weixin.qq.com` 的链接行
4. **整行图片**：`# ![image](url)` 变体（CSDN 抓取常把图片写成标题，会污染标题链）
5. **推广关键词行**：`尼恩Java面试宝典`、`免费领取`、`公众号【技术自由圈】领电子书`、`百度网盘` 等 `PROMO_KEYWORDS` 列表

> 关键点：清洗只删「整行」，不做行内替换，避免误伤正文技术句（如正文里合法出现的「电子书」）。

### 4.2 `corpus/chunk.py` — 分块与四层出处

分块是出处精确性的核心。每块携带 **四层出处**：

```
文件名 → 章节标题链（带行号） → 原文 → 链接
```

实现要点：

- **按 `##` 标题切块**：遇到新标题先结算上一块，标题行本身保留进原文（利于检索命中）。
- **标题链 `stack`**：维护 `[(level, title, lineno)]`，构建 `# 标题（L13） → ## 2.3 RAG范式（L360）` 这种带行号的层级链。
- **`block_section` 变量**：记录「块起始」的标题链而非「块结束」的标题链——否则标题变更会串位（曾在标题切换时把下一章节名记到上一块）。
- **块长 500~800 字**：超 800 字按空行段落再切（`_split_long`），段首保留标题上下文；切分阈值 `SPLIT_AT=600`。
- **URL 来源**：`index.json` 的 `id → url` 映射，URL 固定为 `https://www.cnblogs.com/crazymakercircle/p/{id}.html`。

### 4.3 `corpus/index.py` — 建索引

三个产物，各司其职：

| 产物 | 内容 | 用途 |
|------|------|------|
| `chunks.json` | 每块附 `tokens`（jieba 分词结果） | 检索时直接 `BM25Okapi` 重建 BM25 |
| `vectors.npy` | 每块 512 维向量，L2 归一化 | 向量检索（余弦 = 内积） |
| `corpus.db` | SQLite `chunks` 表（不含 tokens） | 人工查阅/调试 |

向量编码用 **fastembed + `BAAI/bge-small-zh-v1.5`**（ONNX Runtime 后端），**无需 PyTorch**。归一化后余弦相似度退化为内积，检索时一条矩阵乘法即可。

> 索引成本：28134 块，jieba 分词约 3 分钟 + 向量编码约 19 分钟，一次性。向量模型首次运行从 HuggingFace 下载（约 100 MB）。

### 4.4 `resume/parse.py` — 简历解析

输入结构化 JSON（MVP 阶段，PDF 解析列为后续增强）：

```json
{ "name": "...", "skills": [{"name", "level", "evidence"}] , "projects": [...], "depth_signals": [...] }
```

关键设计 —— **evidence 拆子查询**：简历里 `evidence` 是一串关键词，直接拼成单 query 会被强词（如「分布式锁/看门狗」）淹没弱词（如「为什么快」）。因此每个关键词拆成独立子查询：

```python
aspects = [f"{name} {kw}" for kw in evidence.split()]   # "Redis 缓存", "Redis 看门狗", "Redis 为什么快"…
```

这解决了实测中「Redis 为什么快召回不到」的问题。

### 4.5 `retrieve/search.py` — 混合检索 + RRF

双路召回，**RRF（Reciprocal Rank Fusion）** 融合：

```
对每个子查询 aspect：
  BM25 路：jieba 分词 → BM25Okapi 打分 → top-20
  向量路：query 编码 → 归一化 → matrix @ qv（内积） → top-20
  融合：score(d) = Σ 1/(RRF_K + rank_i)，RRF_K=60
```

**多子查询合并去重**：`retrieve_bundle` 对每个 aspect 各检索 `FINAL_TOPK*3` 条，按 `chunk idx` 去重、保留最高 RRF 分，排序后取 top-5。这样同一技能点下不同关键词召回的片段能合并，且不会被某个强关键词独占。

检索参数集中在 `config.py`：

```python
EMBED_MODEL = "BAAI/bge-small-zh-v1.5"
BM25_TOPK = 20    # BM25 召回数
VEC_TOPK = 20     # 向量召回数
RRF_K = 60        # RRF 平滑系数
FINAL_TOPK = 5    # 每技能点最终片段数
```

### 4.6 `generate/build_prompt.py` — 检索包格式化

把检索包转成 Ducc 可读的 Markdown（`retrieval_bundle.md`）：每技能点 + top 片段，片段含 `标题/文件/章节/链接/原文摘录`。文件头部写入生成规范：

> 答案必须锚定片段，出处精确到「文件名 → 章节 → 原文 → 链接」四层；片段未覆盖处标 ⚠️ 语料外，不得编造。

### 4.7 `generate/inject.py` — 生成与注入

这是「半自动」里的「自动注入」半段。题卷数据（题目+答案+考察点+出处）由 Ducc 在会话里编写，脚本负责：

- **schema v3**：每道题含 `category / id / prompt / title / answerPoints[] / keyPoints / source / followUps[]`；文档含 `candidateSignal / overallNote / risk / recommendation / contentVersion`。
- **注入保护**：覆盖前先 `interview.json` 备份为 `.bak-时间戳`。
- **写入**：`json.dump(ensure_ascii=False, indent=2)` 到 `~/Library/Application Support/InterviewDesk/interview.json`。

---

## 5. 题卷规范（生成侧约定）

这是 RAG 流水线的「质量契约」，由检索包头部的规范承载：

1. **答案锚定片段**：每条 `answerPoints` 以 `【标题】` 前缀组织（背景 → 原理 → 逐条展开）。
2. **四层出处硬约束**：`source` 字段必须是 `文件名 → 章节（带行号） → 原文摘录 → 链接`。
3. **⚠️ 语料外**：检索包未覆盖的内容（如 LightRAG 实现细节、Flink 链路）必须标注，标准答案靠候选人自述校准，不得编造。
4. **追问 `followUps`**：每道题 2 个追问，用于区分「背八股」和「真做过」。

---

## 6. 运行方式

```bash
# 首次（或语料变更）：重建分块 + 索引
python3 main.py --rebuild --resume resume/sample_xuhaoyang.json

# 日常：复用已有索引，只跑检索
python3 main.py --resume resume/sample_xuhaoyang.json

# 生成并注入题卷（Ducc 编好题目后）
python3 generate/inject.py
```

`main.py` 幂等：`chunks.json` / `vectors.npy` 已存在则跳过重建，除非传 `--rebuild`。

---

## 7. 关键设计决策与权衡

| 决策 | 取舍 |
|------|------|
| fastembed 而非 sentence-transformers | 环境无 PyTorch，fastembed 走 ONNX Runtime，CPU 也能跑 |
| RRF 而非分数量纲归一化 | 只依赖排名，天然跳过 BM25 分与向量分的量纲差异 |
| SQLite + numpy 裸文件 | 零运维，无独立向量数据库依赖，MVP 够用 |
| 半自动生成 | 全自动 LLM 出题易编造出处；半自动把「召回」自动化、「编写/校验」留给人，保证出处可查 |
| 子查询拆分 + idx 去重 | 解决多关键词 query 被强词淹没的召回偏差 |

## 8. 已知限制与扩展方向

- **语料覆盖**：698 篇「技术自由圈」语料偏 Java/中间件/大厂面试，前沿点（LightRAG/GraphRAG 实现、Flink/Mafka）未覆盖，题卷里以 ⚠️ 语料外 处理。
- **召回 top-5 局限**：某些经典题（如 Redis 六大架构）top-5 只覆盖部分子节，需更细查询或提高 top-k。
- **简历输入**：当前仅结构化 JSON；PDF 简历解析（pymupdf）可作为增强。
- **生成自动化**：当前题卷题目与答案由 Ducc 手写，可进一步让 `build_prompt.py` 输出结构化的 LLM prompt，接入模型做初稿再人工校验。
- **索引增量更新**：语料更新需 `--rebuild` 全量重建，可改增量。
