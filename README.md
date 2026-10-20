# XScreenCapture

XScreenCapture is a macOS menu bar app built around screenshot frameworks extracted from **your locally installed QQ**. It provides an original AppKit host, build scripts, and reverse-engineering notes. The QQ screenshot engine has not been reconstructed as complete source code. QQ binaries and toolbar images are extracted at build time and are not included in this repository.

Current revision: **0.2.3, build 5**, bundle ID `milu.qqjietu`. The toolbar uses QQ's original button PNGs from the extracted framework's `ThemeResources/QQ-theme`, preserving their shapes, colors, and interaction-state images in the compact **432 × 48 pt** layout.

## Build and launch

Requirements: an Apple Silicon (M-series) Mac running macOS 13+, an Xcode toolchain with Swift 6.1+, Python 3, and QQ.app containing its screenshot plugin with arm64 support. The first build downloads pinned Swift Package dependencies. The analyzed QQ sample is `6.9.86 (36365)`; other versions require compatibility checks.

```sh
# Build for Apple Silicon only. Signing defaults to ad-hoc.
./scripts/build.sh
open build/XScreenCapture.app

# Keep using the same installed signing identity across rebuilds.
./scripts/build.sh --sign "Developer ID Application: Your Name (TEAMID)"

# Optional environment configuration; --qq-app also accepts a QQ.app path.
XSCREEN_CAPTURE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  QQ_APP_PATH="/path/to/QQ.app" ./scripts/build.sh
```

The output is `build/XScreenCapture.app`. The script copies and signs component copies without modifying QQ.app, and preserves the last successful output if a build fails. The host loads its bundled frameworks without launching QQ or the original plugin.

All builds use arm64 for the host and permission bridge, and strip other architecture slices from copied QQ frameworks before signing. `--arch arm64` is accepted explicitly; other architectures are rejected. The resulting app runs natively on Apple Silicon and does not include Intel code. Install the app by copying it to `~/Applications` or `/Applications`; building does not automatically replace an installed copy.

## Use

- Start from the settings window or menu bar. The default shortcut is **⌘⇧2**. Choose “设置…” to reopen settings.
- Click the shortcut recorder and press a combination containing at least one of **⌘, ⌃, or ⌥**, optionally with ⇧. Esc, clicking elsewhere, or losing focus cancels recording. Conflicts preserve the previous shortcut; “恢复默认” restores ⌘⇧2.
- Click the border color swatch to open the system color panel. The setting is saved automatically; its default is blue `#0099FF`. It changes the selection outline, not annotation colors.
- Capture begins with an overlay and no preselected window. Drag to draw a selection; releasing the mouse shows the toolbar. Clicking alone or making a zero-height drag does not select a window. Drag outside an existing selection to replace it and discard its annotations.
- Annotate, copy, or save with the toolbar. Double-click completes a capture; Esc cancels. The toolbar retains the engine's actions and uses its [original QQ button resources](docs/toolbar-design.md).
- Grant screen-recording access using the integrated **PermissionFlow 2.11.3** guide. Quit and reopen the app if it remains unready after authorization.
- Settings also control Retina output and capture sound. The menu offers copying or saving the last image again.

OCR, scrolling capture, and screen recording remain disabled. Normal mode retains the engine's cancellation behavior when the app loses foreground status, hides, or changes Spaces. The fixed 220 ms startup wait and screenshot-window transitions have been removed; capture latency has not been measured.

Keep using the same signing identity when rebuilding an installed app. Nested component copies remain ad-hoc signed, and the app is not notarized. Switching signing identities or rebuilding an ad-hoc host can invalidate screen-recording authorization. If access remains unavailable after authorization, try removing the old permission entry, adding the installed app again, and choosing Quit & Reopen.

## Verification

```sh
python3 scripts/verify_bundle.py build/XScreenCapture.app --qq-app /Applications/QQ.app
build/XScreenCapture.app/Contents/MacOS/XScreenCapture --self-test
```

Bundle verification requires every Mach-O executable and library to contain only arm64, and rejects Intel or Universal components. Self-test checks framework loading and required interfaces; it does not take a screenshot. Original component versions and SHA-256 hashes are recorded in `Contents/Resources/component-manifest.json`. Recheck interfaces after a QQ update.

For **0.2.3**, the Apple Silicon build and installation passed arm64 self-test, dependency/source checks, and strict signature verification. All five Mach-O files contain only arm64; the installed copy matches the build and retains the existing Developer ID signing requirement. Normal launch shows “截图已就绪”. Negative checks reject non-arm64 build arguments, a Universal host, and a Universal framework inside an arm64 app. These checks do not cover the capture/annotation/save flow. Local evidence is recorded in `analysis/self-test/v0.2.3-arm64-verification.json`. The earlier 0.2.2 hand-drawn preview is historical and does not represent the current toolbar; see the [resource and layout notes](docs/toolbar-design.md).

Historical **0.2.1** build/install and normal-mode UI checks passed. They cover manual selection, outside reselection, rectangle annotation, saving a 550 × 124 px PNG, and Esc cancellation. The earlier 19 shortcut-controller checks cover registration, conflict rollback, persistence, and cleanup. These results do not validate the 0.2.3 toolbar. Physical global-key triggering, multiple displays, other annotation tools, cross-app paste, and measured latency remain outside the verified coverage.

The host is in `Sources/XClip` and the permission bridge in `Sources/PermissionBridge`. Local analysis dumps, screenshots, and runtime logs in `analysis/` are excluded from Git. Earlier findings remain in the [reverse-engineering record](docs/逆向记录.md); its evidence filenames refer to those local artifacts.

## Attribution

QQ, JietuFramework, and their resources remain the property of their respective rights holders. AFNetworking and CocoaLumberjack retain their original attribution and licenses. Local extraction and re-signing do not change ownership or automatically grant redistribution rights.

[PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) uses the MIT license, copied into the app as `Contents/Resources/PermissionFlow-LICENSE.txt`. [REA](https://github.com/morluto/rea) 6.4.0 was used for artifact, Mach-O, and dyld inspection; it is not an app runtime dependency.
