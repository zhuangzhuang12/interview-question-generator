# -*- coding: utf-8 -*-
"""常驻检索服务：加载索引后，从 stdin 逐行读 JSON 请求，向 stdout 回一行 JSON 响应。

供 InterviewDesk App 内嵌进程调用（PyInstaller 打包成自包含可执行文件）。
协议（每行一个 JSON，request/response 一一对应）：
  请求 {"action":"ping"}                          -> 响应 {"ok":true,"message":"ready","chunks":N}
  请求 {"action":"retrieve","resume":{...}}        -> 响应 {"ok":true,"bundle":[...]}
  出错                                            -> 响应 {"ok":false,"error":"..."}

环境变量：
  RAG_DATA_DIR   索引数据目录（chunks.json / vectors.npy），默认 config.DATA_DIR
  RAG_CACHE_DIR  fastembed 模型缓存目录，默认 fastembed 自带临时目录
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from retrieve.search import Retriever, retrieve_bundle


def parse_resume_data(data):
    """把原始简历 JSON 转成检索器需要的 queries（每个 evidence 关键词拆一个子查询）。"""
    queries = []
    for s in data.get("skills", []):
        name = s.get("name", "")
        evidence = s.get("evidence", "")
        aspects = [f"{name} {kw}" for kw in evidence.split()]
        queries.append({
            "skill": name,
            "level": s.get("level", ""),
            "evidence": evidence,
            "aspects": aspects,
        })
    return {"name": data.get("name", ""), "queries": queries}


def main():
    retriever = Retriever()
    sys.stderr.write(f"[rag_server] ready, chunks={len(retriever.chunks)}\n")
    sys.stderr.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            _reply({"ok": False, "error": f"JSON 解析失败: {e}"})
            continue

        action = req.get("action", "")
        if action == "ping":
            _reply({"ok": True, "message": "ready", "chunks": len(retriever.chunks)})
        elif action == "retrieve":
            try:
                resume = req.get("resume") or {}
                parsed = parse_resume_data(resume)
                bundle = retrieve_bundle(parsed, retriever=retriever)
                _reply({"ok": True, "bundle": bundle})
            except Exception as e:  # noqa: BLE001
                _reply({"ok": False, "error": str(e)})
        else:
            _reply({"ok": False, "error": f"未知 action: {action}"})


def _reply(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
