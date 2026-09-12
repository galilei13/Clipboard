import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916), xRadius: 208, yRadius: 208)
        NSGradient(starting: NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.93, alpha: 1),
                   ending: NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.64, alpha: 1))!.draw(in: background, angle: -65)
        NSColor.white.withAlphaComponent(0.96).setStroke()
        let board = NSBezierPath(roundedRect: NSRect(x: 285, y: 222, width: 454, height: 564), xRadius: 65, yRadius: 65)
        board.lineWidth = 44; board.stroke()
        NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.80, alpha: 1).setFill()
        let tab = NSBezierPath(roundedRect: NSRect(x: 400, y: 732, width: 224, height: 113), xRadius: 33, yRadius: 33)
        tab.fill(); NSColor.white.setStroke(); tab.lineWidth = 38; tab.stroke()
        for (y, width) in [(620, 248), (508, 248), (396, 160)] {
            NSColor.white.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: NSRect(x: 390, y: y, width: width, height: 34), xRadius: 17, yRadius: 17).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
