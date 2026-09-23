# -*- coding: utf-8 -*-
"""全局路径与常量。"""
import os

APP_DIR = os.path.dirname(os.path.abspath(__file__))          # interview_app/
LORA_DIR = os.path.dirname(APP_DIR)                            # lora/

# 语料
CORPUS_MD_DIR = os.path.join(LORA_DIR, "crazymakercircle_blog", "md")
INDEX_JSON = os.path.join(LORA_DIR, "crazymakercircle_blog", "index.json")

# 数据输出（RAG_DATA_DIR 允许在打包/分发时重定向到 App 内资源）
DATA_DIR = os.environ.get("RAG_DATA_DIR", os.path.join(APP_DIR, "data"))
CHUNKS_JSON = os.path.join(DATA_DIR, "chunks.json")
VECTORS_NPY = os.path.join(DATA_DIR, "vectors.npy")
CORPUS_DB = os.path.join(DATA_DIR, "corpus.db")
RETRIEVAL_BUNDLE_JSON = os.path.join(DATA_DIR, "retrieval_bundle.json")
RETRIEVAL_BUNDLE_MD = os.path.join(DATA_DIR, "retrieval_bundle.md")

# 检索参数
EMBED_MODEL = "BAAI/bge-small-zh-v1.5"
BM25_TOPK = 20
VEC_TOPK = 20
RRF_K = 60
FINAL_TOPK = 5
