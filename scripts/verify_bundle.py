#!/usr/bin/env python3
"""校验 XScreenCapture 的依赖闭包、架构、签名与本地提取来源；不执行第三方代码。"""

import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path


FRAMEWORKS = ("AFNetworking", "CocoaLumberjack", "JietuFramework")
BRIDGE_DYLIB = "libXClipPermissionBridge.dylib"
PERMISSION_RESOURCES = "PermissionFlow_PermissionFlow.bundle"
MANIFEST_NAME = "component-manifest.json"
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


class VerificationError(Exception):
    pass


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise VerificationError(f"命令失败：{' '.join(map(str, args))}\n{result.stderr.strip()}")
    return result.stdout


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inside(path, parent):
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def bundle_identity(bundle):
    is_framework = bundle.suffix == ".framework"
    plist = bundle / ("Resources/Info.plist" if is_framework else "Contents/Info.plist")
    metadata = read_plist(plist)
    executable_name = metadata["CFBundleExecutable"]
    executable = bundle / executable_name if is_framework else bundle / "Contents/MacOS" / executable_name
    if not inside(executable, bundle) or not executable.is_file():
        raise VerificationError(f"可执行文件不在 bundle 内或不存在：{executable}")
    return {
        "bundle_path": str(bundle.resolve()),
        "bundle_identifier": metadata.get("CFBundleIdentifier"),
        "version": metadata.get("CFBundleShortVersionString"),
        "build": metadata.get("CFBundleVersion"),
        "executable_path": str(executable.resolve()),
        "executable_sha256": sha256(executable),
    }


def plugin_path(qq_app):
    return qq_app / "Contents/Resources/app/QQ ScreenCapture plugin.app"


def write_manifest(app, qq_app):
    plugin = plugin_path(qq_app)
    components = []
    for name in FRAMEWORKS:
        source = bundle_identity(plugin / "Contents/Frameworks" / f"{name}.framework")
        copied = bundle_identity(app / "Contents/Frameworks" / f"{name}.framework")
        components.append({
            "name": name,
            "source": source,
            "bundled_executable": str(Path(copied["executable_path"]).relative_to(app)),
            "bundled_executable_sha256": copied["executable_sha256"],
        })
    manifest = {
        "schema_version": 1,
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "note": "组件仅从本机 QQ 提取；副本仅保留 arm64 并经过 ad-hoc 签名，源文件未修改。此记录不表示腾讯授权再分发。",
        "source_qq": bundle_identity(qq_app),
        "source_plugin": bundle_identity(plugin),
        "components": components,
    }
    resolved = json.loads((Path(__file__).resolve().parents[1] / "Package.resolved").read_text())
    dependency = next(pin for pin in resolved["pins"] if pin["identity"] == "permissionflow")
    manifest["permission_bridge"] = {
        "bundled_executable": f"Contents/Frameworks/{BRIDGE_DYLIB}",
        "bundled_executable_sha256": sha256(app / "Contents/Frameworks" / BRIDGE_DYLIB),
        "resource_bundle": f"Contents/Resources/{PERMISSION_RESOURCES}",
        "dependency": dependency,
    }
    path = app / "Contents/Resources" / MANIFEST_NAME
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"已记录 QQ / 截图插件版本及来源 SHA-256：{path.name}")


def architectures(binary):
    return set(run("/usr/bin/xcrun", "lipo", "-archs", str(binary)).split())


def rpaths(binary, arch):
    output = run("/usr/bin/otool", "-arch", arch, "-l", str(binary))
    return re.findall(r"\bcmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset \d+\)", output)


def dependencies(binary, arch):
    output = run("/usr/bin/otool", "-arch", arch, "-L", str(binary))
    return [line.strip().split(" (compatibility version", 1)[0]
            for line in output.splitlines() if line.startswith("\t")]


def expand_loader_path(value, loader, executable):
    if value == "@loader_path" or value.startswith("@loader_path/"):
        return loader.parent / value[len("@loader_path"):].lstrip("/")
    if value == "@executable_path" or value.startswith("@executable_path/"):
        return executable.parent / value[len("@executable_path"):].lstrip("/")
    if value.startswith("/"):
        return Path(value)
    raise VerificationError(f"不支持的动态库路径：{value}")


def verify_dependencies(app, executable):
    wanted_archs = architectures(executable)
    if wanted_archs != {"arm64"}:
        raise VerificationError(f"宿主必须仅包含 arm64：实际为 {sorted(wanted_archs)}")
    binaries = []
    for path in app.rglob("*"):
        if path.is_symlink():
            if not path.exists() or not inside(path, app):
                raise VerificationError(f"bundle 含悬空或越界符号链接：{path}")
            continue
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO_MAGICS:
                    binaries.append(path.resolve())
    framework_dir = app / "Contents/Frameworks"
    actual = {path.name for path in framework_dir.iterdir()}
    expected = {f"{name}.framework" for name in FRAMEWORKS} | {BRIDGE_DYLIB}
    if actual != expected:
        raise VerificationError(f"提取组件不符合白名单：{sorted(actual)}")
    binary_set = set(binaries)
    for binary in binaries:
        available = architectures(binary)
        if available != wanted_archs:
            raise VerificationError(f"{binary.name} 必须仅包含 arm64：实际为 {sorted(available)}")
        for arch in sorted(wanted_archs):
            inherited = [expand_loader_path(value, executable, executable)
                         for value in rpaths(executable, arch)]
            local = [expand_loader_path(value, binary, executable) for value in rpaths(binary, arch)]
            if binary.name == BRIDGE_DYLIB:
                for value in rpaths(binary, arch):
                    if value.startswith("/") and not value.startswith(("/usr/lib/", "/System/Library/")):
                        raise VerificationError(f"桥接库依赖本机构建路径：{value}")
            for dependency in dependencies(binary, arch):
                # 系统动态库可能仅存在于 dyld shared cache，不要求磁盘中存在文件。
                if dependency.startswith(("/System/Library/", "/usr/lib/")):
                    continue
                if dependency.startswith("@rpath/"):
                    suffix = dependency[len("@rpath/"):]
                    candidates = [base / suffix for base in local + inherited]
                else:
                    candidates = [expand_loader_path(dependency, binary, executable)]
                resolved = next((item.resolve() for item in candidates if item.is_file()), None)
                if resolved is None or not inside(resolved, app) or resolved not in binary_set:
                    raise VerificationError(f"依赖未闭合：{binary.name} [{arch}] → {dependency}")
    print(f"依赖闭包通过：{len(binaries)} 个 Mach-O；架构 {', '.join(sorted(wanted_archs))}")


def verify_manifest(app, qq_app):
    path = app / "Contents/Resources" / MANIFEST_NAME
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise VerificationError("不支持的来源 manifest 版本。")
    components = manifest.get("components", [])
    if sorted(item["name"] for item in components) != sorted(FRAMEWORKS):
        raise VerificationError("manifest 组件列表不符合白名单。")
    for item in components:
        binary = app / item["bundled_executable"]
        if not inside(binary, app) or sha256(binary) != item["bundled_executable_sha256"]:
            raise VerificationError(f"副本哈希不符：{item['name']}")
    bridge = manifest["permission_bridge"]
    bridge_binary = app / bridge["bundled_executable"]
    if (bridge["bundled_executable"] != f"Contents/Frameworks/{BRIDGE_DYLIB}"
            or not inside(bridge_binary, app)
            or sha256(bridge_binary) != bridge["bundled_executable_sha256"]):
        raise VerificationError("权限桥接库路径或 SHA-256 不符。")
    resources = app / bridge["resource_bundle"]
    if bridge["resource_bundle"] != f"Contents/Resources/{PERMISSION_RESOURCES}":
        raise VerificationError("PermissionFlow 资源 bundle 路径异常。")
    for locale in ("en", "zh-hans"):
        # SwiftPM 在 macOS 上将语言目录规范化为小写。
        if not (resources / f"{locale}.lproj/Localizable.strings").is_file():
            raise VerificationError(f"PermissionFlow 缺少语言资源：{locale}")
    if not (app / "Contents/Resources/PermissionFlow-LICENSE.txt").is_file():
        raise VerificationError("缺少 PermissionFlow MIT 许可副本。")
    if qq_app is not None:
        source_pairs = [(qq_app, manifest["source_qq"]),
                        (plugin_path(qq_app), manifest["source_plugin"])]
        source_pairs.extend((plugin_path(qq_app) / "Contents/Frameworks" / f"{item['name']}.framework",
                             item["source"]) for item in components)
        for bundle, recorded in source_pairs:
            current = bundle_identity(bundle)
            for key in ("bundle_identifier", "version", "build", "executable_sha256"):
                if current[key] != recorded[key]:
                    raise VerificationError(f"QQ 来源已变化：{bundle.name} 的 {key} 不符。")
        print("来源校验通过：QQ、截图插件及 framework 的版本/哈希与提取记录一致")
    else:
        print("副本 SHA-256 校验通过；未指定 --qq-app，跳过本机源文件比对")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="待验证的 XScreenCapture.app")
    parser.add_argument("--qq-app", type=Path, help="同时校验该 QQ.app 的来源哈希")
    parser.add_argument("--write-manifest", action="store_true", help="在宿主签名前写入来源 manifest")
    args = parser.parse_args()
    app = args.app.resolve()
    qq_app = args.qq_app.resolve() if args.qq_app else None
    try:
        if args.write_manifest:
            if qq_app is None:
                parser.error("--write-manifest 需要 --qq-app")
            write_manifest(app, qq_app)
        else:
            metadata = read_plist(app / "Contents/Info.plist")
            executable = app / "Contents/MacOS" / metadata["CFBundleExecutable"]
            if not inside(executable, app):
                raise VerificationError("宿主 executable 路径越界。")
            verify_dependencies(app, executable)
            verify_manifest(app, qq_app)
            for name in FRAMEWORKS:
                run("/usr/bin/codesign", "--verify", "--strict", "--verbose=2",
                    str(app / "Contents/Frameworks" / f"{name}.framework"))
            run("/usr/bin/codesign", "--verify", "--strict", "--verbose=2",
                str(app / "Contents/Frameworks" / BRIDGE_DYLIB))
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
            print("codesign 严格校验通过")
    except (VerificationError, OSError, ValueError, KeyError, StopIteration) as error:
        print(f"验证失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
