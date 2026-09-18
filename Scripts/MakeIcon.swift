import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("需要提供 iconset 目录。") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(red: 0.16, green: 0.29, blue: 0.51, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210).fill()
        for index in 0..<3 {
            let y = 248 + index * 188
            NSColor.white.withAlphaComponent(index == 2 ? 1 : 0.20).setFill()
            NSBezierPath(roundedRect: NSRect(x: 222, y: y, width: 580, height: 144), xRadius: 43, yRadius: 43).fill()
            NSColor(red: 0.31, green: 0.55, blue: 0.96, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 257, y: y + 39, width: 66, height: 66)).fill()
            NSColor(red: 0.16, green: 0.29, blue: 0.51, alpha: index == 2 ? 1 : 0.8).setFill()
            NSBezierPath(roundedRect: NSRect(x: 363, y: y + 62, width: 180 + index * 42, height: 20), xRadius: 10, yRadius: 10).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("无法生成应用图标。") }
        try data.write(to: url)
    }
}
