#!/usr/bin/env swift
import AppKit
import Foundation

// Vector source for the icon. No downloads, fonts, or third-party tools required.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? repository.appendingPathComponent("Resources/AppIcon.icns")
let scratch = repository.appendingPathComponent(".build/icon-artwork")
let iconset = scratch.appendingPathComponent("AppIcon.iconset")
let files = FileManager.default
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
try files.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func stroke(_ from: NSPoint, _ to: NSPoint, color ink: NSColor, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineCapStyle = .round
    path.lineWidth = width
    ink.setStroke()
    path.stroke()
}

func drawArtwork() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908), xRadius: 198, yRadius: 198)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -9)
    shadow.shadowBlurRadius = 22
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.set()
    color(15, 37, 42).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(8, 27, 35), color(23, 69, 70)])!.draw(in: tile, angle: 70)
    tile.lineWidth = 2
    NSColor.white.withAlphaComponent(0.13).setStroke()
    tile.stroke()

    // The broad handle sits behind the lens, with an inset highlight.
    NSGraphicsContext.saveGraphicsState()
    let handleShadow = NSShadow()
    handleShadow.shadowOffset = NSSize(width: 0, height: -8)
    handleShadow.shadowBlurRadius = 22
    handleShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    handleShadow.set()
    stroke(NSPoint(x: 607, y: 414), NSPoint(x: 777, y: 244), color: color(31, 162, 153), width: 88)
    NSGraphicsContext.restoreGraphicsState()
    stroke(NSPoint(x: 620, y: 428), NSPoint(x: 789, y: 259), color: color(106, 228, 205, 0.60), width: 13)

    let glass = NSBezierPath(ovalIn: NSRect(x: 224, y: 338, width: 464, height: 464))
    NSGradient(colors: [color(17, 57, 65), color(24, 91, 91)])!.draw(in: glass, angle: 85)

    // One root branches into three ports inside the inspection lens.
    let wire = color(101, 219, 201)
    stroke(NSPoint(x: 332, y: 570), NSPoint(x: 459, y: 570), color: wire, width: 22)
    stroke(NSPoint(x: 459, y: 464), NSPoint(x: 459, y: 676), color: wire, width: 22)
    for y: CGFloat in [464, 570, 676] {
        stroke(NSPoint(x: 459, y: y), NSPoint(x: 569, y: y), color: wire, width: 22)
    }
    for point in [NSPoint(x: 332, y: 570), NSPoint(x: 569, y: 464), NSPoint(x: 569, y: 570), NSPoint(x: 569, y: 676)] {
        let node = NSBezierPath(ovalIn: NSRect(x: point.x - 28, y: point.y - 28, width: 56, height: 56))
        color(209, 255, 242).setFill()
        node.fill()
    }

    // A crisp outer rim keeps the silhouette recognizable at Dock sizes.
    let rim = NSBezierPath(ovalIn: NSRect(x: 224, y: 338, width: 464, height: 464))
    rim.lineWidth = 32
    color(104, 232, 209).setStroke()
    rim.stroke()
    let innerRim = NSBezierPath(ovalIn: NSRect(x: 246, y: 360, width: 420, height: 420))
    innerRim.lineWidth = 3
    NSColor.white.withAlphaComponent(0.20).setStroke()
    innerRim.stroke()
}

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PortLens.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the icon bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawArtwork()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PortLens.Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode the icon PNG."])
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    try png(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try png(size: 1024).write(to: scratch.appendingPathComponent("preview.png"))

let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else {
    throw NSError(domain: "PortLens.Icon", code: Int(converter.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}
print("Generated \(output.path)")
