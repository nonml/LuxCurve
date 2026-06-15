#!/usr/bin/env swift
//
//  make-icon.swift
//  LuxCurve tooling
//
//  Renders the app icon set programmatically so the artwork is reproducible and
//  reviewable in source rather than a binary blob. Run from the repo root:
//
//      swift Tooling/make-icon.swift
//
//  It writes PNGs + Contents.json into LuxCurve/Assets.xcassets/AppIcon.appiconset.
//  The motif: a sun over a day→dusk gradient with a rising "comfort curve".
//

import AppKit

let outDir = "LuxCurve/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func draw(size s: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-rect plate with the standard macOS transparent margin.
    let inset = s * 0.085
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: s * 0.20, yRadius: s * 0.20)
    plate.addClip()

    // Day → dusk vertical gradient.
    let top = NSColor(srgbRed: 1.00, green: 0.74, blue: 0.26, alpha: 1)   // warm amber
    let bottom = NSColor(srgbRed: 0.11, green: 0.16, blue: 0.30, alpha: 1) // deep indigo
    NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)

    // Sun, upper-left-ish.
    let sunR = s * 0.16
    let sunC = NSPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.66)
    NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)).fill()

    // Rays.
    let rayPath = NSBezierPath()
    rayPath.lineWidth = s * 0.022
    rayPath.lineCapStyle = .round
    for i in 0..<8 {
        let a = CGFloat(i) / 8 * .pi * 2
        let r0 = sunR * 1.28, r1 = sunR * 1.62
        rayPath.move(to: NSPoint(x: sunC.x + cos(a) * r0, y: sunC.y + sin(a) * r0))
        rayPath.line(to: NSPoint(x: sunC.x + cos(a) * r1, y: sunC.y + sin(a) * r1))
    }
    NSColor(srgbRed: 1, green: 0.95, blue: 0.80, alpha: 0.92).setStroke()
    rayPath.stroke()

    // Rising comfort curve (a smooth S from lower-left to upper-right).
    let curve = NSBezierPath()
    curve.lineWidth = s * 0.045
    curve.lineCapStyle = .round
    curve.lineJoinStyle = .round
    let p0 = NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.30)
    let p3 = NSPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.52)
    let c1 = NSPoint(x: lerp(p0.x, p3.x, 0.45), y: rect.minY + rect.height * 0.20)
    let c2 = NSPoint(x: lerp(p0.x, p3.x, 0.55), y: rect.minY + rect.height * 0.66)
    curve.move(to: p0)
    curve.curve(to: p3, controlPoint1: c1, controlPoint2: c2)
    NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95).setStroke()
    curve.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// (filename, pixel size) for the macOS icon set.
let pixels: [Int] = [16, 32, 64, 128, 256, 512, 1024]
for px in pixels {
    let data = draw(size: CGFloat(px))
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(px).png"))
}

// Asset catalog manifest mapping idiom/size/scale → file.
struct Img { let size: Int; let scale: Int }
let entries: [Img] = [
    Img(size: 16, scale: 1), Img(size: 16, scale: 2),
    Img(size: 32, scale: 1), Img(size: 32, scale: 2),
    Img(size: 128, scale: 1), Img(size: 128, scale: 2),
    Img(size: 256, scale: 1), Img(size: 256, scale: 2),
    Img(size: 512, scale: 1), Img(size: 512, scale: 2),
]
let images = entries.map { e -> String in
    let px = e.size * e.scale
    return """
        {
          "idiom" : "mac",
          "size" : "\(e.size)x\(e.size)",
          "scale" : "\(e.scale)x",
          "filename" : "icon_\(px).png"
        }
    """
}.joined(separator: ",\n")
let contents = """
{
  "images" : [
\(images)
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("Wrote \(pixels.count) PNGs + Contents.json to \(outDir)")
