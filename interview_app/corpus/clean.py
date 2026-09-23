# -*- coding: utf-8 -*-
"""行级清洗：去掉文首推广段、元数据、传送门等噪音，保留技术正文与标题结构。"""
import re

# 命中即删整行的推广关键词（保守，避免误删正文技术句）
PROMO_KEYWORDS = [
    "尼恩Java面试宝典", "免费赠送", "免费领取", "免费获取", "领电子书", "加尼恩",
    "读者交流群", "百度网盘", "学习圣经", "技术圣经", "圣经PDF",
    "疯狂创客圈总目录", "关注公众号", "涨薪必备", "技术自由圈", "面试宝典PDF",
    "领取方式", "电子书", "电子版", "总目录",
]

_LINK_LINE = re.compile(r"^\[.*\]\(https?://")

# 整行是图片（CSDN 抓取常把图片写成 "# ![在这里插入图片描述](url)"，会污染标题链）
_IMG_LINE = re.compile(r"^#{0,4}\s*!\[[^\]]*\]\(https?://[^)]*\)\s*$")

# 「本文原文地址 / 原始地址 / 传送门」类导航标题（多种变体，整行删除）
_PORTAL_H = re.compile(
    r"^#{1,4}\s*("
    r"本文.{0,20}(原文|原始)"      # 本文原文 / 本文的原文地址 / 本文的原始地址…传送门
    r"|原文\s*地址\s*$"             # 原文地址
    r"|原始的内容"                   # 原始的内容，请参考本文的原文地址
    r"|平台篇幅限制"                 # 平台篇幅限制，原始的内容…
    r"|\[本文.{0,20}(原文|原始).{0,10}\]"  # [本文原文链接/地址](…) 链接式传送门
    r")"
)


def clean_text(text: str) -> str:
    """清洗单篇 markdown 文本，返回清洗后的文本。"""
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if not s:
            out.append(line)
            continue
        # 1. 元数据 blockquote（原文链接 / 日期）
        if s.startswith("> 原文：") or s.startswith("> 日期："):
            continue
        # 2. 传送门/原文地址导航标题
        if _PORTAL_H.match(s):
            continue
        # 3. mp.weixin / 公众号传送门链接行
        if "mp.weixin.qq.com" in s and _LINK_LINE.match(s):
            continue
        # 3.5 整行图片（含 "# ![image](url)" 的标题污染变体）
        if _IMG_LINE.match(s):
            continue
        # 4. 推广关键词行
        if any(k in s for k in PROMO_KEYWORDS):
            continue
        out.append(line)
    return "\n".join(out)
