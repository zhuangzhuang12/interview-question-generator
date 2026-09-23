# -*- coding: utf-8 -*-
"""混合检索：BM25 + 向量双路召回，RRF 融合，输出带四层出处的 top-k 片段。"""
import json
import os

import jieba
import numpy as np
from fastembed import TextEmbedding
from rank_bm25 import BM25Okapi

from config import CHUNKS_JSON, VECTORS_NPY, EMBED_MODEL, BM25_TOPK, VEC_TOPK, RRF_K, FINAL_TOPK

jieba.setLogLevel(20)


class Retriever:
    def __init__(self):
        self.chunks = json.load(open(CHUNKS_JSON, encoding="utf-8"))
        self.bm25 = BM25Okapi([c["tokens"] for c in self.chunks])
        self.matrix = np.load(VECTORS_NPY)  # 已归一化
        self.model = TextEmbedding(model_name=EMBED_MODEL, cache_dir=os.environ.get("RAG_CACHE_DIR"))

    def search(self, query, k=FINAL_TOPK):
        # BM25 召回
        toks = list(jieba.lcut(query))
        bm25_scores = self.bm25.get_scores(toks)
        bm25_top = np.argsort(bm25_scores)[::-1][:BM25_TOPK]

        # 向量召回（余弦 = 内积，因已归一化）
        qv = np.asarray(list(self.model.embed([query]))[0], dtype="float32")
        qv = qv / (np.linalg.norm(qv) + 1e-8)
        sims = self.matrix @ qv
        vec_top = np.argsort(sims)[::-1][:VEC_TOPK]

        # RRF 融合
        rrf = {}
        bm25_set = set(bm25_top.tolist())
        vec_set = set(vec_top.tolist())
        for rank, idx in enumerate(bm25_top.tolist()):
            rrf[idx] = rrf.get(idx, 0.0) + 1.0 / (RRF_K + rank + 1)
        for rank, idx in enumerate(vec_top.tolist()):
            rrf[idx] = rrf.get(idx, 0.0) + 1.0 / (RRF_K + rank + 1)

        ranked = sorted(rrf.items(), key=lambda x: -x[1])[:k]
        out = []
        for idx, score in ranked:
            c = self.chunks[idx]
            out.append({
                "idx": idx,
                "file": c["file"],
                "title": c["title"],
                "section": c["section"],
                "text": c["text"][:400],
                "url": c["url"],
                "score": round(score, 5),
                "bm25_rank": (bm25_top.tolist().index(idx) + 1) if idx in bm25_set else None,
                "vec_rank": (vec_top.tolist().index(idx) + 1) if idx in vec_set else None,
            })
        return out


def retrieve_bundle(resume_data, retriever=None):
    if retriever is None:
        retriever = Retriever()
    bundle = []
    for q in resume_data["queries"]:
        # 每个子查询（aspect）各检索，按 chunk idx 去重、保留最高 RRF 分
        merged = {}
        for aspect in q["aspects"]:
            for res in retriever.search(aspect, k=FINAL_TOPK * 3):
                i = res["idx"]
                if i not in merged or res["score"] > merged[i]["score"]:
                    merged[i] = res
        results = sorted(merged.values(), key=lambda x: -x["score"])[:FINAL_TOPK]
        bundle.append({
            "skill": q["skill"],
            "level": q["level"],
            "evidence": q["evidence"],
            "query": " | ".join(q["aspects"]),
            "chunks": results,
        })
    return bundle
