# Toolbar resources — 0.2.3

Version `0.2.3` / build `5` uses the original QQ screenshot button PNGs from the locally extracted framework's `ThemeResources/QQ-theme`. The previous hand-drawn artwork is no longer the current toolbar design.

## Resources and layout

The 11 buttons are rectangle, ellipse, arrow, pen, mosaic, text, numbered marker, undo, save, cancel, and done. Original shapes, colors, hover images, and selected images are retained. Each image uses a 24 pt logical size with a 48 px @2x representation, centered within a 32 pt button.

QQ's undo configuration references a missing selected image; the implementation uses its actual pressed resource for that state. The other button images come from the existing theme resources. Targets, actions, and annotation behavior remain with the original screenshot engine; OCR and scrolling capture remain disabled.

The compact layout remains **432 × 48 pt**, with **32 pt** buttons, **4 pt** gaps within groups, **8 pt** outer padding, and two separators. It removes the former 660 pt toolbar's trailing empty area.

## Preview utility

[render-toolbar-preview.m](../scripts/render-toolbar-preview.m) now requires two arguments: the output PNG path and the `QQ-theme` directory. For example, after compiling the utility:

```sh
/tmp/xscreencapture-toolbar-preview /tmp/qq-toolbar-icons.png \
  "build/XScreenCapture.app/Contents/Frameworks/JietuFramework.framework/Resources/ThemeResources/QQ-theme"
```

The local `analysis/evidence/v0.2.2-toolbar-icons.png` is historical hand-drawn artwork and must not be used as a preview of 0.2.3. Analysis artifacts are excluded from Git.

## Delivery scope

The 0.2.3 change was built and installed. **No additional self-tests, preview runs, or UI tests were performed for 0.2.3.** Earlier 0.2.1 machine checks and UI evidence remain local historical records; they do not validate these new toolbar resources or geometry.

The QQ images retain their original ownership and attribution. Local extraction does not grant redistribution rights.
