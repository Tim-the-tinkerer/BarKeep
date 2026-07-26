#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.06
    let corner = s * 0.22
    let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Deep slate → indigo gradient (menu bar / night desk feel)
    let colors = [
        CGColor(srgbRed: 0.22, green: 0.28, blue: 0.48, alpha: 1),
        CGColor(srgbRed: 0.12, green: 0.14, blue: 0.28, alpha: 1),
        CGColor(srgbRed: 0.06, green: 0.07, blue: 0.14, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }

    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 0.75, green: 0.82, blue: 1.0, alpha: 0.28))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(path)
    ctx.strokePath()

    drawMenuBarGlyph(in: ctx, size: s, bounds: rect)
    return ctx.makeImage()
}

func drawMenuBarGlyph(in ctx: CGContext, size s: CGFloat, bounds: CGRect) {
    let ink = CGColor(srgbRed: 0.92, green: 0.95, blue: 1.0, alpha: 0.95)
    let accent = CGColor(srgbRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.95)

    // Menu bar strip
    let barH = s * 0.11
    let barY = bounds.maxY - s * 0.28
    let barX = bounds.minX + s * 0.16
    let barW = bounds.width - s * 0.32
    let barRect = CGRect(x: barX, y: barY, width: barW, height: barH)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barH * 0.35, cornerHeight: barH * 0.35, transform: nil)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.addPath(barPath)
    ctx.fillPath()

    // Status dots on the right (visible section)
    let dotR = s * 0.028
    let dotsY = barRect.midY
    var dx = barRect.maxX - s * 0.06
    for i in 0..<3 {
        ctx.setFillColor(i == 0 ? accent : ink)
        ctx.fillEllipse(in: CGRect(x: dx - dotR, y: dotsY - dotR, width: dotR * 2, height: dotR * 2))
        dx -= s * 0.07
    }

    // Divider line
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(max(1.5, s * 0.012))
    ctx.setLineCap(.round)
    let divX = barRect.minX + barW * 0.42
    ctx.move(to: CGPoint(x: divX, y: barRect.minY + barH * 0.2))
    ctx.addLine(to: CGPoint(x: divX, y: barRect.maxY - barH * 0.2))
    ctx.strokePath()

    // Faded dots left of divider (hidden section)
    ctx.setFillColor(CGColor(srgbRed: 0.92, green: 0.95, blue: 1.0, alpha: 0.28))
    dx = divX - s * 0.08
    for _ in 0..<3 {
        ctx.fillEllipse(in: CGRect(x: dx - dotR, y: dotsY - dotR, width: dotR * 2, height: dotR * 2))
        dx -= s * 0.065
    }

    // Chevron below
    let chevronY = bounds.minY + s * 0.28
    let cx = bounds.midX
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(max(2.0, s * 0.035))
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    let arm = s * 0.08
    ctx.move(to: CGPoint(x: cx + arm * 0.4, y: chevronY + arm))
    ctx.addLine(to: CGPoint(x: cx - arm * 0.6, y: chevronY))
    ctx.addLine(to: CGPoint(x: cx + arm * 0.4, y: chevronY - arm))
    ctx.strokePath()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "GenerateAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write \(url.lastPathComponent)"])
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Assets/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("diana.k@example.org", 32),
    ("icon_32x32.png", 32),
    ("ivan.p@example.net", 64),
    ("icon_128x128.png", 128),
    ("wendy.h@example.net", 256),
    ("icon_256x256.png", 256),
    ("wendy.h@example.net", 512),
    ("icon_512x512.png", 512),
    ("walt.e@example.net", 1024),
]

for (name, size) in specs {
    guard let image = renderIcon(size: size) else {
        fputs("Failed to render \(size)\n", stderr)
        exit(1)
    }
    try writePNG(image, to: iconset.appendingPathComponent(name))
}

let png1024 = root.appendingPathComponent("Assets/AppIcon-1024.png")
if let image = renderIcon(size: 1024) {
    try writePNG(image, to: png1024)
}

let icns = root.appendingPathComponent("Assets/AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

print("Wrote \(icns.path)")
