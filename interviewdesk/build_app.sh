#!/bin/bash
# 打包 InterviewDesk.app：编译 + 组装 bundle + 内嵌 RAG 检索资源 + 签名（+ 可选公证）。
#
# 用法：
#   ./build_app.sh                          # 编译、组装、ad-hoc 签名（本机可用）
#   CODESIGN_IDENTITY="Apple Development: ..." ./build_app.sh   # 用指定证书签名
#   NOTARIZE=1 APPLE_ID=... APP_PASSWORD=... TEAM_ID=... ./build_app.sh  # 签名 + 公证 + staple
#
# 路径可用环境变量覆盖：
#   RAG_SRC_DIR    —— RAG 流水线根目录（默认 /Users/guozhuangzhuang02/baidu/lora/interview_app）
#   APP_OUTPUT_DIR —— .app 输出目录（默认 /Applications）
#   ICONSET_DIR    —— iconset 目录（默认 ../icon/InterviewDesk.iconset）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="InterviewDesk"
BUNDLE_ID="local.interviewdesk.app"

RAG_SRC_DIR="${RAG_SRC_DIR:-/Users/guozhuangzhuang02/baidu/lora/interview_app}"
APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-/Applications}"
ICONSET_DIR="${ICONSET_DIR:-$(cd "$PROJECT_DIR/../icon" && pwd)/InterviewDesk.iconset}"

APP="$APP_OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
RAG_RES="$RES/rag"

IDENTITY="${CODESIGN_IDENTITY:-}"

echo "==> 1/5 编译 release"
cd "$PROJECT_DIR"
swift build -c release

echo "==> 2/5 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$RES"

cp "$PROJECT_DIR/.build/release/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS/Info.plist"

if [ -d "$ICONSET_DIR" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$RES/$APP_NAME.icns"
else
    echo "!! 未找到 iconset（$ICONSET_DIR），跳过图标"
fi

echo "==> 3/5 内嵌 RAG 检索资源"
mkdir -p "$RAG_RES/data" "$RAG_RES/models"
# PyInstaller --onedir：rag_server 二进制 + _internal（须与二进制同级）
cp -R "$RAG_SRC_DIR/dist/rag_server/rag_server" "$RAG_RES/rag_server"
cp -R "$RAG_SRC_DIR/dist/rag_server/_internal" "$RAG_RES/_internal"
# 检索运行时数据（chunks + vectors，不含 corpus.db）
cp "$RAG_SRC_DIR/data/chunks.json" "$RAG_RES/data/chunks.json"
cp "$RAG_SRC_DIR/data/vectors.npy" "$RAG_RES/data/vectors.npy"
# fastembed 模型缓存
cp -R "$RAG_SRC_DIR/dist/models/." "$RAG_RES/models/"

echo "==> 4/5 签名"
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --options runtime --timestamp \
        --sign "$IDENTITY" "$APP"
    echo "    已用证书签名：$IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "    已 ad-hoc 签名（本机可用；分发需 Developer ID 证书 + 公证）"
fi

echo "==> 5/5 完成"
if [ "${NOTARIZE:-0}" = "1" ]; then
    if [ -z "$IDENTITY" ]; then
        echo "!! 公证需要签名证书，请设置 CODESIGN_IDENTITY（Developer ID Application）" >&2
        exit 1
    fi
    echo "==> 提交公证"
    ditto -c -k --keepParent "$APP" "$APP.zip"
    xcrun notarytool submit "$APP.zip" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    rm -f "$APP.zip"
    echo "==> staple"
    xcrun stapler staple "$APP"
fi

du -sh "$APP" 2>/dev/null || true
echo "完成：$APP"
