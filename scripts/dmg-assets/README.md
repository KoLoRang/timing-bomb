# DMG installation background

`background.png` (660 × 360) and `background@2x.png` (1320 × 720) contain only
a curved arrow on transparency, without a frame, solid canvas, or text.
`dmgbuild` combines both into a Retina-aware background inside the disk image.

To regenerate them on macOS, from the repository root:

```sh
swift scripts/generate-dmg-background.swift scripts/dmg-assets
```

Keep the arrow between the two icon positions in `scripts/dmg-settings.py`.
