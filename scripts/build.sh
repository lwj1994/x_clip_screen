#!/bin/bash
# 从本机 QQ 提取截图组件并构建宿主，任何步骤失败都保留上次成功的产物。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XScreenCapture"
QQ_PATH="${QQ_APP_PATH:-/Applications/QQ.app}"
ARCH="arm64"
SIGNING_IDENTITY="${XSCREEN_CAPTURE_SIGNING_IDENTITY:--}"

usage() {
  cat <<'EOF'
用法：scripts/build.sh [QQ.app 路径] [--qq-app 路径] [--arch arm64] [--sign 签名身份]

默认读取 QQ_APP_PATH，未设置时读取 /Applications/QQ.app。
仅构建 Apple Silicon（M 系列芯片）的 arm64 版本，包含所有随包依赖。
--sign 签署宿主；也可通过 XSCREEN_CAPTURE_SIGNING_IDENTITY 指定，默认 - 为 ad-hoc。
本机更新应持续使用同一有效签名身份及 bundle ID，避免屏幕录制授权因二进制哈希变化而失配。
成功产物：build/XScreenCapture.app。仅复制并重新签名副本，不修改 QQ.app。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qq-app)
      [[ $# -ge 2 ]] || { echo "错误：--qq-app 缺少路径。" >&2; exit 2; }
      QQ_PATH="$2"; shift 2 ;;
    --arch)
      [[ $# -ge 2 ]] || { echo "错误：--arch 缺少架构。" >&2; exit 2; }
      ARCH="$2"; shift 2 ;;
    --sign)
      [[ $# -ge 2 && -n "$2" ]] || { echo "错误：--sign 缺少签名身份。" >&2; exit 2; }
      SIGNING_IDENTITY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "错误：未知选项 $1" >&2; usage >&2; exit 2 ;;
    *) QQ_PATH="$1"; shift ;;
  esac
done

[[ "$(uname -s)" == Darwin ]] || { echo "错误：构建需要 macOS。" >&2; exit 1; }
[[ "$ARCH" == arm64 ]] || { echo "错误：仅支持 Apple Silicon 架构 arm64，不支持 ${ARCH}。" >&2; exit 2; }
for tool in xcrun python3 codesign ditto; do
  command -v "$tool" >/dev/null || { echo "错误：缺少 $tool，请先配置 Xcode Command Line Tools。" >&2; exit 1; }
done
xcrun --find clang >/dev/null
xcrun --find swift >/dev/null
[[ -d "$QQ_PATH" ]] || { echo "错误：找不到 QQ.app：$QQ_PATH" >&2; exit 1; }
QQ_PATH="$(cd "$QQ_PATH" && pwd -P)"
PLUGIN="$QQ_PATH/Contents/Resources/app/QQ ScreenCapture plugin.app"
SOURCE_FRAMEWORKS="$PLUGIN/Contents/Frameworks"
FRAMEWORKS=(CocoaLumberjack AFNetworking JietuFramework)
for framework in "${FRAMEWORKS[@]}"; do
  [[ -f "$SOURCE_FRAMEWORKS/$framework.framework/$framework" ]] || {
    echo "错误：当前 QQ 缺少 $framework.framework；该 QQ 版本的截图组件布局可能已改变。" >&2
    exit 1
  }
  xcrun lipo "$SOURCE_FRAMEWORKS/$framework.framework/$framework" -verify_arch arm64 || {
    echo "错误：$framework.framework 缺少 arm64，无法用于 Apple Silicon 构建。" >&2
    exit 1
  }
done
[[ -f "$ROOT/Sources/XScreenCapture/main.swift" && -f "$ROOT/Resources/Info.plist" ]] || {
  echo "错误：缺少 Sources/XScreenCapture/main.swift 或 Resources/Info.plist。" >&2; exit 1;
}

mkdir -p "$ROOT/build"
OUTPUT="$ROOT/build/$APP_NAME.app"
[[ ! -L "$OUTPUT" ]] || { echo "错误：拒绝替换符号链接 $OUTPUT。" >&2; exit 1; }
STAGING="$(mktemp -d "$ROOT/build/.xscreencapture-build.XXXXXX")"
APP="$STAGING/$APP_NAME.app"
PREVIOUS="$STAGING/previous.app"
cleanup() {
  local result=$?
  if [[ -e "$PREVIOUS" && ! -e "$OUTPUT" ]]; then
    mv "$PREVIOUS" "$OUTPUT" || echo "错误：旧产物保留在 $PREVIOUS，请手动恢复。" >&2
  fi
  if [[ ! -e "$PREVIOUS" || -e "$OUTPUT" ]]; then
    rm -rf "$STAGING"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

printf '正在编译 %s 与 PermissionFlow 权限引导桥接（%s）……\n' "$APP_NAME" "$ARCH"
SWIFT_SCRATCH="$ROOT/build/swiftpm"
SWIFT_OPTIONS=(--package-path "$ROOT" --scratch-path "$SWIFT_SCRATCH" \
  -c release --triple arm64-apple-macosx13.0 --force-resolved-versions)
xcrun swift build "${SWIFT_OPTIONS[@]}" --product XClipPermissionBridge
xcrun swift build "${SWIFT_OPTIONS[@]}" --product "$APP_NAME"
SWIFT_BIN="$(xcrun swift build "${SWIFT_OPTIONS[@]}" --show-bin-path)"
PERMISSION_RESOURCES="$SWIFT_BIN/PermissionFlow_PermissionFlow.bundle"
BRIDGE="$APP/Contents/Frameworks/libXClipPermissionBridge.dylib"
cp "$SWIFT_BIN/libXClipPermissionBridge.dylib" "$BRIDGE"
xcrun install_name_tool -id '@rpath/libXClipPermissionBridge.dylib' "$BRIDGE"
HOST="$APP/Contents/MacOS/$APP_NAME"
cp "$SWIFT_BIN/$APP_NAME" "$HOST"
# SwiftPM 会加入当前 Xcode 工具链的 rpath；发布副本只使用系统 Swift runtime。
python3 - "$BRIDGE" "$HOST" <<'PY'
import re
import subprocess
import sys

for binary in sys.argv[1:]:
    output = subprocess.check_output(["/usr/bin/otool", "-l", binary], text=True)
    rpaths = re.findall(r"\bcmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset \d+\)", output)
    for path in sorted(set(rpaths)):
        if path.startswith("/") and not path.startswith(("/usr/lib/", "/System/Library/")):
            subprocess.run(["/usr/bin/xcrun", "install_name_tool", "-delete_rpath", path, binary], check=True)
PY
ditto --noextattr --norsrc --noqtn "$PERMISSION_RESOURCES" \
  "$APP/Contents/Resources/PermissionFlow_PermissionFlow.bundle"
cp "$SWIFT_SCRATCH/checkouts/PermissionFlow/LICENSE" "$APP/Contents/Resources/PermissionFlow-LICENSE.txt"
codesign --force --sign - --timestamp=none "$BRIDGE"

printf '正在从本机 QQ 复制截图组件：%s\n' "$QQ_PATH"
for framework in "${FRAMEWORKS[@]}"; do
  # ditto 保留版本化 framework 的符号链接；不继承 QQ 的扩展属性或隔离标记。
  ditto --noextattr --norsrc --noqtn \
    "$SOURCE_FRAMEWORKS/$framework.framework" "$APP/Contents/Frameworks/$framework.framework"
  # Resolve the versioned executable so thinning preserves framework symlinks.
  FRAMEWORK_BINARY="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' \
    "$APP/Contents/Frameworks/$framework.framework/$framework")"
  if [[ "$(xcrun lipo -archs "$FRAMEWORK_BINARY")" != arm64 ]]; then
    xcrun lipo "$FRAMEWORK_BINARY" -thin arm64 -output "$STAGING/$framework.arm64"
    mv "$STAGING/$framework.arm64" "$FRAMEWORK_BINARY"
  fi
  codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/$framework.framework"
done

# manifest 收录原始 QQ / 插件 executable 及已签名的 framework 副本。
# 宿主最终签名后其 executable 会改变，因此不在自身的资源 manifest 中记录宿主哈希。
python3 "$ROOT/scripts/verify_bundle.py" "$APP" --write-manifest --qq-app "$QQ_PATH"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
python3 "$ROOT/scripts/verify_bundle.py" "$APP" --qq-app "$QQ_PATH"

if [[ -e "$OUTPUT" ]]; then
  mv "$OUTPUT" "$PREVIOUS"
fi
mv "$APP" "$OUTPUT"
printf '\n构建完成：%s\n启动命令：open "%s"\n' "$OUTPUT" "$OUTPUT"
