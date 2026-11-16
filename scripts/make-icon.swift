#!/usr/bin/swift
// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output.icns] [preview.png]

import AppKit
import CoreGraphics

/// Draws the icon on a 1024-point canvas with the origin in the lower left corner:
/// a yellow note with a curled corner, three lines of writing and an insertion point.
func drawIcon(in ctx: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    // Soft shadow under the note.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28))
    ctx.addPath(platePath)
    ctx.setFillColor(color(1.00, 0.76, 0.20))
    ctx.fillPath()
    ctx.restoreGState()

    // The note, lighter at the top.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let paper = CGGradient(
        colorsSpace: space,
        colors: [color(1.00, 0.89, 0.42), color(1.00, 0.74, 0.18)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        paper, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])

    // The curled corner, lower right: a shadow on the note, then the lifted flap.
    let fold: CGFloat = 250
    let corner = CGPoint(x: plate.maxX, y: plate.minY)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -10, height: 10), blur: 30, color: color(0.45, 0.25, 0, 0.45))
    ctx.move(to: CGPoint(x: corner.x - fold, y: corner.y))
    ctx.addLine(to: CGPoint(x: corner.x - fold, y: corner.y + fold))
    ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + fold))
    ctx.closePath()
    ctx.setFillColor(color(1.00, 0.95, 0.70))
    ctx.fillPath()
    ctx.restoreGState()
    // What shows behind the lifted corner.
    ctx.move(to: CGPoint(x: corner.x - fold, y: corner.y))
    ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + fold))
    ctx.addLine(to: corner)
    ctx.closePath()
    ctx.setFillColor(color(0.80, 0.50, 0.05))
    ctx.fillPath()
    ctx.restoreGState()

    // Three lines of writing.
    ctx.setStrokeColor(color(0.42, 0.27, 0.04, 0.88))
    ctx.setLineWidth(50)
    ctx.setLineCap(.round)
    for (y, endX) in [(CGFloat(712), CGFloat(700)), (CGFloat(572), CGFloat(790)), (CGFloat(432), CGFloat(470))] {
        ctx.move(to: CGPoint(x: 236, y: y))
        ctx.addLine(to: CGPoint(x: endX, y: y))
        ctx.strokePath()
    }

    // The insertion point, ready after the last word.
    let caret = CGRect(x: 528, y: 372, width: 30, height: 120)
    ctx.addPath(CGPath(roundedRect: caret, cornerWidth: 15, cornerHeight: 15, transform: nil))
    ctx.setFillColor(color(0.13, 0.42, 0.95))
    ctx.fillPath()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try png(pixels: pixels).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(output)")

if arguments.count > 2 {
    try png(pixels: 512).write(to: URL(fileURLWithPath: arguments[2]))
    print("Wrote \(arguments[2])")
}
