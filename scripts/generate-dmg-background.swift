#!/usr/bin/env swift
import AppKit

// A transparent, borderless guide lets Finder supply the window background,
// including when the user enlarges the window. No text is baked into the image.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 660 * scale, pixelsHigh: 360 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: 660, height: 360)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    context.cgContext.clear(CGRect(x: 0, y: 0, width: 660, height: 360))
    let accent = NSColor(calibratedRed: 0.42, green: 0.52, blue: 1, alpha: 0.8)
    accent.setStroke()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x, y: 360 - y)
    }
    let arrow = NSBezierPath()
    arrow.move(to: point(245, 168))
    arrow.curve(to: point(418, 162),
                controlPoint1: point(286, 116), controlPoint2: point(365, 115))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: point(400, 158))
    head.line(to: point(418, 162))
    head.line(to: point(413, 144))
    head.lineWidth = 2.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? "" : "@2x"
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: outputDirectory.appendingPathComponent("background\(suffix).png")
    )
}
