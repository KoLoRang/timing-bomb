# TimingBomb 图标

图像由 CPAMC `gpt-image-2.5` 生成。App 使用已确认的黑白地雷与摇杆造型，菜单栏版本去掉高光与细节，缩小后保留轮廓。

| 文件 | 用途 |
| --- | --- |
| `AppIcon.png` | 1024 × 1024 App 主图，标准 macOS 留白及透明圆角 |
| `AppIcon.icns` | Finder / Dock / 应用图标，含 16–1024 px 的标准表示 |
| `AppIcon.iconset/` | ICNS 对应的 10 张 PNG |
| `MenuBarTemplate.png`, `MenuBarTemplate@2x.png` | 18 pt 菜单栏模板：18 / 36 px，透明底，纯黑形状 |
| `MenuBar16Template.png`, `MenuBar16Template@2x.png` | 更小的 16 pt 版本：16 / 32 px |
| `Preview.png` | App 图标及菜单栏图标的明暗背景预览 |
| `Sources/` | 已确认的 App 原图与 CPAMC 菜单栏生成原图 |

`scripts/make-app.sh` 将 ICNS 与菜单栏 PNG 复制到 `.app/Contents/Resources/`，并设置 `CFBundleIconFile`。当前应用没有顶部菜单栏入口，这里提供对应资源，不添加菜单栏功能。

接入菜单栏时请使用 `NSImage.isTemplate = true`（或 SwiftUI 的 `.renderingMode(.template)`），使用 18 × 18 pt 或 16 × 16 pt 的显示尺寸。图像仅用黑色 RGB 加透明通道，系统会根据菜单栏外观显示黑色或白色，无需另存白色文件。`@2x` 文件用于 Retina 显示。

需要重新导出时，在 macOS 上使用安装了 Pillow 的 Python：

```sh
python3 scripts/generate-icons.py
./scripts/make-app.sh
```

日常打包直接使用已导出的资源，不需要 Pillow，也不会调用图片 API。
