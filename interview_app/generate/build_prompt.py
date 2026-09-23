# -*- coding: utf-8 -*-
"""把检索包格式化为给 Ducc 阅读的 Markdown（每个技能点 + 带四层出处的 top 片段）。"""


def bundle_to_markdown(bundle, name):
    lines = [f"# 检索包：{name}", ""]
    lines.append("> 说明：以下片段由「BM25 + 向量」混合检索（RRF 融合）召回，供出题时锚定标准答案与出处。")
    lines.append("> 生成规范：答案必须锚定片段，出处精确到「文件名 → 章节 → 原文 → 链接」四层；片段未覆盖处标 ⚠️ 语料外，不得编造。")
    lines.append("")
    for item in bundle:
        lines.append(f"## 技能点：{item['skill']}（{item['level']}）")
        lines.append(f"查询：{item['query']}")
        lines.append("")
        if not item["chunks"]:
            lines.append("（无召回片段）")
            lines.append("")
            continue
        for i, c in enumerate(item["chunks"], 1):
            lines.append(f"### [{i}] {c['title']}")
            lines.append(f"- 文件：`{c['file']}`")
            lines.append(f"- 章节：{c['section']}")
            lines.append(f"- 链接：{c['url']}")
            lines.append(f"- 原文摘录：{c['text']}")
            lines.append("")
    return "\n".join(lines)
