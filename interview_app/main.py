# -*- coding: utf-8 -*-
"""一键入口：简历 →（可选重建索引）→ 混合检索 → 输出检索包。"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import CHUNKS_JSON, VECTORS_NPY, RETRIEVAL_BUNDLE_JSON, RETRIEVAL_BUNDLE_MD
from corpus.chunk import chunk_all
from corpus.index import build as build_index
from generate.build_prompt import bundle_to_markdown
from resume.parse import parse_resume
from retrieve.search import retrieve_bundle


def main():
    ap = argparse.ArgumentParser(description="面试出题 RAG：简历 → 检索包")
    ap.add_argument("--resume", default="resume/sample_xxx.json", help="简历 JSON 路径")
    ap.add_argument("--rebuild", action="store_true", help="强制重新分块 + 建索引")
    args = ap.parse_args()

    if args.rebuild or not os.path.exists(CHUNKS_JSON):
        chunk_all()
    if args.rebuild or not os.path.exists(VECTORS_NPY):
        build_index()

    resume = parse_resume(args.resume)
    print(f"简历：{resume['name']}，技能点 {len(resume['queries'])} 个\n")

    bundle = retrieve_bundle(resume)

    os.makedirs(os.path.dirname(RETRIEVAL_BUNDLE_JSON), exist_ok=True)
    with open(RETRIEVAL_BUNDLE_JSON, "w", encoding="utf-8") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=1)
    with open(RETRIEVAL_BUNDLE_MD, "w", encoding="utf-8") as f:
        f.write(bundle_to_markdown(bundle, resume["name"]))

    for item in bundle:
        print(f"【{item['skill']}】top-{len(item['chunks'])}:")
        for c in item["chunks"]:
            print(f"   - {c['file'][:52]} | {c['section'][:38]}")
        print()

    print(f"检索包已写出：{RETRIEVAL_BUNDLE_MD}")


if __name__ == "__main__":
    main()
