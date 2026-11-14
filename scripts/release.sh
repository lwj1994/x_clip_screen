#!/bin/bash
# 构建、公证并发布 XScreenCapture：DMG 供用户下载，.app.zip 供 App 内自动更新。
# App 内更新只接受与当前 App 同一签名身份的 .app.zip，因此发布必须使用固定身份。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${XSCREEN_CAPTURE_SIGNING_IDENTITY:-}"
NOTES_FILE=""

usage() {
  cat <<'EOF'
用法：scripts/release.sh [--sign 签名身份] [--notes-file 文件]

版本号读取 Resources/Info.plist 的 CFBundleShortVersionString，tag 为 v<版本>。
签名身份也可通过 XSCREEN_CAPTURE_SIGNING_IDENTITY 指定；不允许 ad-hoc。
流程：scripts/distribute.sh 构建 → 公证 → staple → 生成签名 DMG，然后上传
XScreenCapture-<版本>.app.zip 与 XScreenCapture-<版本>.dmg 到 GitHub Release。
未提供 --notes-file 时由 GitHub 自动生成发布说明。要求工作区干净且 HEAD 已推送到 origin。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign)
      [[ $# -ge 2 && -n "$2" ]] || { echo "错误：--sign 缺少签名身份。" >&2; exit 2; }
      SIGNING_IDENTITY="$2"; shift 2 ;;
    --notes-file)
      [[ $# -ge 2 && -f "$2" ]] || { echo "错误：--notes-file 需要已存在的文件。" >&2; exit 2; }
      NOTES_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]] || {
  echo "错误：发布需要 Developer ID 签名身份（--sign 或 XSCREEN_CAPTURE_SIGNING_IDENTITY）。" >&2; exit 2;
}
command -v gh >/dev/null || { echo "错误：缺少 gh。" >&2; exit 1; }
cd "$ROOT"
VERSION="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "错误：工作区有未提交改动。" >&2; exit 1; }
git fetch --quiet origin
[[ -n "$(git branch -r --contains HEAD)" ]] || { echo "错误：HEAD 尚未推送到 origin。" >&2; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "错误：Release $TAG 已存在，请先升级 Info.plist 版本号。" >&2; exit 1
fi

# 构建、公证、staple 并生成 DMG；任何一步失败都不会进入上传。
"$ROOT/scripts/distribute.sh" --sign "$SIGNING_IDENTITY"

APP="$ROOT/build/XScreenCapture.app"
ZIP="$ROOT/dist/XScreenCapture-$VERSION.app.zip"
DMG="$ROOT/dist/XScreenCapture-$VERSION.dmg"
for artifact in "$ZIP" "$DMG"; do
  [[ -f "$artifact" ]] || { echo "错误：缺少产物 $artifact" >&2; exit 1; }
done
[[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" == "$VERSION" ]] || {
  echo "错误：构建产物版本与 Info.plist 不一致。" >&2; exit 1;
}
TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ -n "$TEAM" && "$TEAM" != "not set" ]] || { echo "错误：产物没有签名团队，无法用于自动更新。" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "错误：DMG 未 staple。" >&2; exit 1; }
shasum -a 256 "$ZIP" "$DMG"

NOTES_ARGS=(--generate-notes)
[[ -z "$NOTES_FILE" ]] || NOTES_ARGS=(--notes-file "$NOTES_FILE")
gh release create "$TAG" "$ZIP" "$DMG" --target "$(git rev-parse HEAD)" \
  --title "XScreenCapture $TAG" "${NOTES_ARGS[@]}"
