#!/bin/bash
# 构建 → 公证 .app → staple → 生成签名 DMG → 公证 DMG → staple → Gatekeeper 校验。
# 公证需要 App Store Connect API Key（ASC_KEY_ID / ASC_PRIVATE_KEY_PATH / ASC_ISSUER_ID），
# 或 notarytool 的 keychain profile（--keychain-profile）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XScreenCapture"
IDENTITY="${XSCREEN_CAPTURE_SIGNING_IDENTITY:-}"
KEYCHAIN_PROFILE=""
NOTARIZE=1
SELF_TEST=1
KEEP_WORK=0

usage() {
  cat <<'EOF'
用法：scripts/distribute.sh [--sign 身份] [--keychain-profile 名称] [--no-notarize] [--no-self-test] [--keep-work]

--sign 必填（或设置 XSCREEN_CAPTURE_SIGNING_IDENTITY），必须是 Developer ID Application 身份；
不允许 ad-hoc。产物输出到 dist/：

  XScreenCapture-<版本>.app.zip   App 内自动更新使用，包含已 staple 的 .app
  XScreenCapture-<版本>.dmg       面向用户下载，已签名、公证并 staple

公证凭据优先读取环境变量 ASC_KEY_ID / ASC_PRIVATE_KEY_PATH / ASC_ISSUER_ID，
也接受 --keychain-profile（对应 notarytool store-credentials 保存的档案）。
--no-notarize 只构建本地 DMG，产物无法通过 Gatekeeper，禁止用于发布。
--no-self-test 跳过宿主的 --self-test 冒烟检查。
--keep-work 保留临时目录（公证上传包、DMG 暂存目录、自检输出），便于排查。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign)
      [[ $# -ge 2 && -n "$2" ]] || { echo "错误：--sign 缺少签名身份。" >&2; exit 2; }
      IDENTITY="$2"; shift 2 ;;
    --keychain-profile)
      [[ $# -ge 2 && -n "$2" ]] || { echo "错误：--keychain-profile 缺少名称。" >&2; exit 2; }
      KEYCHAIN_PROFILE="$2"; shift 2 ;;
    --no-notarize) NOTARIZE=0; shift ;;
    --no-self-test) SELF_TEST=0; shift ;;
    --keep-work) KEEP_WORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] || {
  echo "错误：公证需要 Developer ID 签名身份（--sign 或 XSCREEN_CAPTURE_SIGNING_IDENTITY）。" >&2; exit 2;
}
for tool in codesign ditto hdiutil python3 shasum; do
  command -v "$tool" >/dev/null || { echo "错误：缺少 $tool。" >&2; exit 1; }
done

NOTARY_MODE="none"
NOTARY_ARGS=()
if [[ "$NOTARIZE" == 1 ]]; then
  command -v curl >/dev/null || { echo "错误：缺少 curl。" >&2; exit 1; }
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_PRIVATE_KEY_PATH:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    [[ -f "$ASC_PRIVATE_KEY_PATH" ]] || {
      echo "错误：ASC_PRIVATE_KEY_PATH 指向的文件不存在：$ASC_PRIVATE_KEY_PATH" >&2; exit 1;
    }
    if command -v asc >/dev/null; then
      NOTARY_MODE="asc"
    else
      NOTARY_MODE="notarytool"
      NOTARY_ARGS=(--key "$ASC_PRIVATE_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
    fi
  elif [[ -n "$KEYCHAIN_PROFILE" ]]; then
    NOTARY_MODE="notarytool"
    NOTARY_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
  else
    echo "错误：缺少公证凭据。请设置 ASC_KEY_ID / ASC_PRIVATE_KEY_PATH / ASC_ISSUER_ID，" >&2
    echo "      或使用 --keychain-profile 指定 notarytool 保存的档案。" >&2
    exit 1
  fi
fi

VERSION="$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleShortVersionString"])' \
  "$ROOT/Resources/Info.plist")"
APP="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
ZIP="$ROOT/dist/$APP_NAME-$VERSION.app.zip"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/xsc-distribute.XXXXXX")"
cleanup() {
  [[ "$KEEP_WORK" == 1 ]] || rm -rf "$WORK"
  [[ "$KEEP_WORK" == 1 ]] && echo "中间文件保留在 $WORK" >&2
  return 0
}
trap cleanup EXIT

# 把 notarytool / asc 的输出统一整理成 submission-id 与 status。
parse_submission() {
  python3 -c '
import json, re, sys
raw = sys.stdin.read()
match = re.search(r"\{.*\}", raw, re.S)
if not match:
    print("-")
    print("未知")
    raise SystemExit
doc = json.loads(match.group(0))
data = doc.get("data", doc)
attributes = data.get("attributes", data)
print(data.get("id") or attributes.get("id") or "-")
print(attributes.get("status") or doc.get("status") or "未知")
'
}

print_issues() {
  python3 -c '
import json, sys
doc = json.load(sys.stdin)
summary = doc.get("statusSummary") or ""
print("状态：{}；{}".format(doc.get("status", "未知"), summary).rstrip("；"))
issues = doc.get("issues") or []
if not issues:
    print("公证日志没有给出具体问题条目。")
for issue in issues[:20]:
    print("- {}: {} | {}".format(issue.get("severity", "error"),
                                issue.get("path", ""), issue.get("message", "")))
'
}

notary_log() {
  local submission_id="$1" url
  [[ "$submission_id" != "-" ]] || { echo "未取得提交 ID，无法读取日志。" >&2; return 0; }
  if [[ "$NOTARY_MODE" == "asc" ]]; then
    url="$(asc notarization log --id "$submission_id" 2>/dev/null | python3 -c '
import json, sys
raw = sys.stdin.read()
import re
match = re.search(r"\{.*\}", raw, re.S)
print(json.loads(match.group(0))["data"]["attributes"]["developerLogUrl"] if match else "")
')"
    [[ -n "$url" ]] || { echo "无法获取公证日志地址。" >&2; return 0; }
    curl -fsSL "$url" | print_issues
  else
    xcrun notarytool log "$submission_id" "${NOTARY_ARGS[@]}" --output-format json 2>/dev/null | print_issues
  fi
}

notarize() {
  local file="$1" out status submission_id rc=0
  printf '正在提交公证：%s\n' "$(basename "$file")"
  if [[ "$NOTARY_MODE" == "asc" ]]; then
    out="$(asc notarization submit --file "$file" --wait 2>&1)" || rc=$?
  else
    out="$(xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait --output-format json 2>&1)" || rc=$?
  fi
  PARSED="$(printf '%s' "$out" | parse_submission)"
  submission_id="$(printf '%s\n' "$PARSED" | sed -n 1p)"
  status="$(printf '%s\n' "$PARSED" | sed -n 2p)"
  [[ -n "$submission_id" ]] || submission_id="-"
  [[ -n "$status" ]] || status="未知"

  if [[ "$status" != "Accepted" ]]; then
    echo "错误：公证未通过（状态 ${status}，退出码 ${rc}）。" >&2
    printf '%s\n' "$out" >&2
    notary_log "$submission_id" >&2
    exit 1
  fi
  printf '公证通过：%s\n' "$status"
}

stapled_check() {
  local target="$1"
  xcrun stapler validate "$target" >/dev/null || {
    echo "错误：staple 校验失败：$target" >&2; exit 1;
  }
  echo "staple 校验通过：$(basename "$target")"
}

printf '构建 %s %s（%s）……\n' "$APP_NAME" "$VERSION" "$IDENTITY"
"$ROOT/scripts/build.sh" --sign "$IDENTITY"

if [[ "$SELF_TEST" == 1 ]]; then
  printf '运行宿主自检……\n'
  "$APP/Contents/MacOS/$APP_NAME" --self-test >"$WORK/self-test.json" || {
    echo "错误：宿主 --self-test 失败，详见 $WORK/self-test.json" >&2; exit 1;
  }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("engineLoaded") is True and d.get("entrypointsAvailable", 0) > 0' \
    "$WORK/self-test.json" >/dev/null 2>&1 || {
    echo "错误：宿主自检结果不符合预期。" >&2; cat "$WORK/self-test.json" >&2; exit 1;
  }
  echo "宿主自检通过"
fi

python3 "$ROOT/scripts/verify_bundle.py" "$APP" --qq-app "${QQ_APP_PATH:-/Applications/QQ.app}" --distribution

mkdir -p "$ROOT/dist"
if [[ "$NOTARIZE" == 1 ]]; then
  printf '打包公证上传包……\n'
  ditto -c -k --keepParent --sequesterRsrc "$APP" "$WORK/notarize.app.zip"
  notarize "$WORK/notarize.app.zip"
  xcrun stapler staple "$APP"
  stapled_check "$APP"
else
  echo "警告：跳过公证，产物仅用于本机验证。" >&2
fi

codesign --verify --deep --strict "$APP"
python3 "$ROOT/scripts/verify_bundle.py" "$APP" --qq-app "${QQ_APP_PATH:-/Applications/QQ.app}" --distribution --notarized

# 自动更新使用已 staple 的 .app 压缩包，下载后无需联网即可通过 Gatekeeper。
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"

printf '生成磁盘映像……\n'
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto --noextattr --norsrc --noqtn "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG"

if [[ "$NOTARIZE" == 1 ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  stapled_check "$DMG"
fi

printf '\n产物：\n'
for artifact in "$ZIP" "$DMG"; do
  printf '  %s  %s  %s\n' "$(shasum -a 256 "$artifact" | cut -d' ' -f1)" \
    "$(du -h "$artifact" | cut -f1)" "$artifact"
done

if [[ "$NOTARIZE" == 1 ]]; then
  printf '\nGatekeeper 校验：\n'
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/  /' || {
    echo "错误：Gatekeeper 拒绝该 App。" >&2; exit 1;
  }
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | sed 's/^/  /' || {
    echo "错误：Gatekeeper 拒绝该 DMG。" >&2; exit 1;
  }
fi
