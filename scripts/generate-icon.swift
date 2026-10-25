#!/usr/bin/env swift
import AppKit
import Foundation

// Convert the supplied SVG artwork into native app resources without redrawing it.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sources = repository.appendingPathComponent("Resources/Brand")
let runtime = repository.appendingPathComponent("Sources/PortLens/Resources")
let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? repository.appendingPathComponent("Resources/AppIcon.icns")
let scratch = repository.appendingPathComponent(".build/brand-artwork")
let iconset = scratch.appendingPathComponent("AppIcon.iconset")
let files = FileManager.default
for directory in [runtime, iconset, output.deletingLastPathComponent()] {
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
}

func artwork(_ name: String) throws -> NSImage {
    let url = sources.appendingPathComponent(name).appendingPathExtension("svg")
    guard let image = NSImage(contentsOf: url), image.isValid else {
        throw NSError(domain: "PortLens.Brand", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not load \(url.path)"])
    }
    return image
}

func pdf(_ image: NSImage, to destination: URL) throws {
    var bounds = CGRect(origin: .zero, size: image.size)
    guard let context = CGContext(destination as CFURL, mediaBox: &bounds, nil) else {
        throw NSError(domain: "PortLens.Brand", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create \(destination.path)"])
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
}

func png(_ image: NSImage, width: Int, height: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "PortLens.Brand", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create a brand bitmap."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
               from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PortLens.Brand", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode brand PNG."])
    }
    return data
}

for appearance in ["light", "dark"] {
    let name = "portlens-lockup-\(appearance)"
    let image = try artwork(name)
    let destination = runtime.appendingPathComponent(name).appendingPathExtension("pdf")
    try pdf(image, to: destination)
    try png(image, width: 1028, height: 192).write(to: scratch.appendingPathComponent("\(name).png"))
    print("Generated \(destination.path)")
}

let icon = try artwork("portlens-appicon")
for size in [16, 32, 128, 256, 512] {
    try png(icon, width: size, height: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(icon, width: size * 2, height: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try png(icon, width: 1024, height: 1024).write(to: scratch.appendingPathComponent("preview.png"))

let converter = Process()
converter.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
converter.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try converter.run()
converter.waitUntilExit()
guard converter.terminationStatus == 0 else {
    throw NSError(domain: "PortLens.Brand", code: Int(converter.terminationStatus),
                  userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}
print("Generated \(output.path)")
