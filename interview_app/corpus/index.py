# -*- coding: utf-8 -*-
"""建索引：jieba 分词 + fastembed 向量编码，落盘 tokens(chunks.json) / vectors.npy / corpus.db。"""
import json
import sqlite3

import jieba
import numpy as np
from fastembed import TextEmbedding

from config import CHUNKS_JSON, VECTORS_NPY, CORPUS_DB, EMBED_MODEL

jieba.setLogLevel(20)


def build():
    chunks = json.load(open(CHUNKS_JSON, encoding="utf-8"))
    print("分块数:", len(chunks))

    docs = [f"{c['title']}\n{c['text']}" for c in chunks]

    # 1. 分词（BM25 用）
    print("jieba 分词中...")
    for c, d in zip(chunks, docs):
        c["tokens"] = list(jieba.lcut(d))

    # 2. 向量编码
    print("向量编码中...")
    model = TextEmbedding(model_name=EMBED_MODEL)
    vecs = []
    B = 500
    for i in range(0, len(docs), B):
        vecs.extend(list(model.embed(docs[i:i + B])))
        print(f"  {min(i + B, len(docs))}/{len(docs)}")
    matrix = np.vstack([np.asarray(v, dtype="float32") for v in vecs])
    matrix = matrix / (np.linalg.norm(matrix, axis=1, keepdims=True) + 1e-8)
    np.save(VECTORS_NPY, matrix)
    print("向量矩阵:", matrix.shape)

    # 3. SQLite（供人工查阅，不含 tokens）
    conn = sqlite3.connect(CORPUS_DB)
    conn.execute("DROP TABLE IF EXISTS chunks")
    conn.execute("CREATE TABLE chunks (id INTEGER PRIMARY KEY, file TEXT, title TEXT, section TEXT, text TEXT, url TEXT)")
    conn.executemany(
        "INSERT INTO chunks (file,title,section,text,url) VALUES (?,?,?,?,?)",
        [(c["file"], c["title"], c["section"], c["text"], c["url"]) for c in chunks],
    )
    conn.commit()
    conn.close()

    # 4. 写回 chunks.json（含 tokens，供 search 直接重建 BM25）
    with open(CHUNKS_JSON, "w", encoding="utf-8") as f:
        json.dump(chunks, f, ensure_ascii=False, indent=1)
    print("索引完成:", CHUNKS_JSON, VECTORS_NPY, CORPUS_DB)


if __name__ == "__main__":
    build()
