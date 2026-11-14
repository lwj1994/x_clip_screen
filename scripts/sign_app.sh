#!/bin/bash
# 由内向外签名 App bundle：先签所有内嵌 Mach-O，再签 framework bundle，最后签宿主。
# 公证要求：Developer ID 身份 + 硬化运行时（hardened runtime）+ 安全时间戳，三者缺一不可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="-"
ENTITLEMENTS=""
TIMESTAMP="auto"
HARDENED_RUNTIME=1
APP=""
# 默认整体签名；manifest 写入等步骤会把构建拆成“先签内嵌、再签宿主”两段。
SIGN_NESTED=1
SIGN_HOST=1

usage() {
  cat <<'EOF'
用法：scripts/sign_app.sh <App.app> [选项]

  --identity 身份      签名身份，默认 -（ad-hoc）。Developer ID 身份会启用安全时间戳。
  --entitlements 文件  仅对宿主使用的 entitlements plist。
  --no-timestamp       跳过安全时间戳，仅用于离线调试；该产物无法通过公证。
  --no-hardened-runtime
                      关闭硬化运行时，仅用于排查加载问题；该产物无法通过公证。
  --nested-only        只签内嵌 Mach-O 与 framework bundle，不签宿主。
  --host-only          只签宿主，用于 bundle 内资源变更后的重新封装。

默认总是开启硬化运行时，使本地构建与分发构建的加载约束保持一致。
签名顺序固定为：内嵌 Mach-O → *.framework → 宿主 bundle（不使用 --deep）。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      [[ $# -ge 2 && -n "$2" ]] || { echo "错误：--identity 缺少签名身份。" >&2; exit 2; }
      IDENTITY="$2"; shift 2 ;;
    --entitlements)
      [[ $# -ge 2 && -f "$2" ]] || { echo "错误：--entitlements 需要已存在的文件。" >&2; exit 2; }
      ENTITLEMENTS="$2"; shift 2 ;;
    --no-timestamp) TIMESTAMP="none"; shift ;;
    --no-hardened-runtime) HARDENED_RUNTIME=0; shift ;;
    --nested-only) SIGN_HOST=0; shift ;;
    --host-only) SIGN_NESTED=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "错误：未知选项 $1" >&2; usage >&2; exit 2 ;;
    *)
      [[ -z "$APP" ]] || { echo "错误：只能指定一个 App。" >&2; exit 2; }
      APP="$1"; shift ;;
  esac
done

[[ -n "$APP" ]] || { echo "错误：缺少 App 路径。" >&2; usage >&2; exit 2; }
[[ "$SIGN_NESTED" == 1 || "$SIGN_HOST" == 1 ]] || {
  echo "错误：--nested-only 与 --host-only 不能同时使用。" >&2; exit 2;
}
[[ -d "$APP" ]] || { echo "错误：找不到 App：$APP" >&2; exit 1; }
APP="$(cd "$APP" && pwd -P)"
[[ ! -L "$APP" ]] || { echo "错误：签名目标是符号链接：$APP" >&2; exit 1; }

shopt -s nullglob
FRAMEWORKS=("$APP"/Contents/Frameworks/*.framework)
shopt -u nullglob
for framework in "${FRAMEWORKS[@]}"; do
  [[ -f "$framework/Info.plist" || -f "$framework/Resources/Info.plist" ]] || {
    echo "错误：framework 缺少 Info.plist：$framework" >&2; exit 1;
  }
done

if [[ "$IDENTITY" == "-" ]]; then
  # ad-hoc 签名不支持时间戳，公证也无从谈起。
  TIMESTAMP="none"
fi

SIGN_OPTIONS=(--force --sign "$IDENTITY")
if [[ "$HARDENED_RUNTIME" == 1 ]]; then
  SIGN_OPTIONS+=(--options runtime)
fi
if [[ "$TIMESTAMP" != "none" ]]; then
  SIGN_OPTIONS+=(--timestamp)
fi

# 只签真实的 Mach-O 文件；framework 里的版本化符号链接留给 bundle 签名处理。
MACHO_LIST="$(python3 - "$APP" <<'PY'
import pathlib
import sys

MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}
root = pathlib.Path(sys.argv[1])
host = root / "Contents/MacOS"
for path in sorted(root.rglob("*")):
    if path.is_symlink() or not path.is_file() or path.parent == host:
        continue
    try:
        with path.open("rb") as stream:
            if stream.read(4) in MAGICS:
                print(path)
    except OSError:
        continue
PY
)"

if [[ "$SIGN_NESTED" == 1 ]]; then
  if [[ -n "$MACHO_LIST" ]]; then
    while IFS= read -r binary; do
      [[ -n "$binary" ]] || continue
      codesign "${SIGN_OPTIONS[@]}" "$binary"
    done <<< "$MACHO_LIST"
  fi

  for framework in "${FRAMEWORKS[@]}"; do
    codesign "${SIGN_OPTIONS[@]}" "$framework"
  done
fi

if [[ "$SIGN_HOST" == 1 ]]; then
  HOST_OPTIONS=("${SIGN_OPTIONS[@]}")
  [[ -z "$ENTITLEMENTS" ]] || HOST_OPTIONS+=(--entitlements "$ENTITLEMENTS")
  HOST_OPTIONS+=("$APP")
  codesign "${HOST_OPTIONS[@]}"

  codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null 2>&1 || {
    echo "错误：签名校验失败。" >&2; exit 1;
  }
fi

SCOPE="整体"
[[ "$SIGN_NESTED" == 1 ]] || SCOPE="宿主"
[[ "$SIGN_HOST" == 1 ]] || SCOPE="内嵌组件"
if [[ "$IDENTITY" == "-" ]]; then
  echo "已使用 ad-hoc 签名（${SCOPE}）：$APP"
else
  echo "已使用 Developer ID 签名（${SCOPE}）：$APP"
fi
