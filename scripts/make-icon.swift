import AppKit
import Foundation
let mascot = NSImage(contentsOfFile: CommandLine.arguments[2])!
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let inset = CGFloat(pixels) * 0.08
        let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
        NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20).fill()
        mascot.draw(in: rect.insetBy(dx: -CGFloat(pixels) * 0.025, dy: -CGFloat(pixels) * 0.025))
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
    }
}
