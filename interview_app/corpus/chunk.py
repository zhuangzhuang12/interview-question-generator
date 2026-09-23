# -*- coding: utf-8 -*-
"""分块：清洗 + 按 ## 标题切块，块 500~800 字，带四层出处（文件名→章节标题链→原文→链接）。"""
import json
import os
import re

from config import CORPUS_MD_DIR, INDEX_JSON, CHUNKS_JSON, DATA_DIR
from corpus.clean import clean_text

MAX_CHUNK = 800
SPLIT_AT = 600

_H = re.compile(r"^(#{1,4})\s+(.*)$")


def load_url_map():
    with open(INDEX_JSON, encoding="utf-8") as f:
        idx = json.load(f)
    return {item["file"]: item["url"] for item in idx}


def _split_long(chunk):
    """超长块按空行段落再切，段首保留标题上下文。"""
    paras = re.split(r"\n\s*\n", chunk["text"])
    out, buf, n = [], [], 0
    for p in paras:
        buf.append(p)
        n += len(p)
        if n >= SPLIT_AT:
            out.append({**chunk, "text": "\n\n".join(buf).strip()})
            buf, n = [], 0
    if buf:
        out.append({**chunk, "text": "\n\n".join(buf).strip()})
    return out


def chunk_text(md_text: str, file: str, url: str):
    """对一篇清洗后的 md 文本分块，返回 chunk 列表。"""
    chunks = []
    title = ""                 # 文章标题（h1）
    stack = []                 # 标题链 [(level, title, lineno)]
    cur_section = ""           # 当前最新标题链
    block_section = ""         # 当前块起始的标题链（用于出处定位）
    cur_text = []

    def flush():
        nonlocal cur_text
        text = "\n".join(cur_text).strip()
        if text:
            chunks.append({
                "file": file,
                "title": title,
                "section": block_section,
                "text": text,
                "url": url,
            })
        cur_text = []

    for i, line in enumerate(md_text.split("\n"), 1):
        s = line.rstrip("\n")
        m = _H.match(s)
        if m:
            level = len(m.group(1))
            heading = m.group(2).strip()
            # 遇到新标题，先结算上一块（用 block_section）
            if cur_text and level <= 2:
                flush()
            if level == 1:
                title = heading
                stack = [(1, heading, i)]
            else:
                while stack and stack[-1][0] >= level:
                    stack.pop()
                stack.append((level, heading, i))
            cur_section = " → ".join(f"{'#' * lv} {t}（L{ln}）" for lv, t, ln in stack)
            if not cur_text:
                block_section = cur_section
            cur_text.append(s)  # 标题行也保留进原文，便于检索命中
            continue
        if not cur_text and not s.strip():
            continue  # 跳过块首空行
        if not cur_text:
            block_section = cur_section
        cur_text.append(s)
    flush()

    result = []
    for c in chunks:
        if len(c["text"]) <= MAX_CHUNK:
            result.append(c)
        else:
            result.extend(_split_long(c))
    return result


def chunk_all():
    """清洗 + 分块全量语料，写出 chunks.json，返回 chunk 列表。"""
    os.makedirs(DATA_DIR, exist_ok=True)
    url_map = load_url_map()
    files = sorted(f for f in os.listdir(CORPUS_MD_DIR) if f.endswith(".md"))
    all_chunks = []
    for f in files:
        path = os.path.join(CORPUS_MD_DIR, f)
        with open(path, encoding="utf-8") as fp:
            md = fp.read()
        cleaned = clean_text(md)
        url = url_map.get(f, "")
        all_chunks.extend(chunk_text(cleaned, f, url))
    with open(CHUNKS_JSON, "w", encoding="utf-8") as fp:
        json.dump(all_chunks, fp, ensure_ascii=False, indent=1)
    return all_chunks


if __name__ == "__main__":
    cs = chunk_all()
    print("分块完成，共", len(cs), "块 ->", CHUNKS_JSON)
