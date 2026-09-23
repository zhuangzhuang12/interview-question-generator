# -*- coding: utf-8 -*-
"""解析结构化简历 JSON，抽取「技能点 + 检索 query + 深度信号」。"""
import json


def parse_resume(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    queries = []
    for s in data.get("skills", []):
        name = s.get("name", "")
        evidence = s.get("evidence", "")
        # 每个证据关键词拆一个子查询，避免「分布式锁/看门狗」等强词淹没「为什么快」等弱词
        aspects = [f"{name} {kw}" for kw in evidence.split()]
        queries.append({
            "skill": name,
            "level": s.get("level", ""),
            "evidence": evidence,
            "aspects": aspects,
        })
    return {
        "name": data.get("name", ""),
        "queries": queries,
        "depth_signals": data.get("depth_signals", []),
        "projects": data.get("projects", []),
    }
