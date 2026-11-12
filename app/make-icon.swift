// Draws the app icon: make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1),
                        NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)])!
        .draw(in: shape, angle: -90)
    // three stripes: BO1 orange, BO2 blue, BO3 red
    let colors = [NSColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1),
                  NSColor(red: 0.20, green: 0.75, blue: 0.95, alpha: 1),
                  NSColor(red: 0.90, green: 0.20, blue: 0.25, alpha: 1)]
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    let w = rect.width / 3
    for (i, c) in colors.enumerated() {
        c.setFill()
        NSRect(x: rect.minX + CGFloat(i) * w, y: rect.minY, width: w, height: rect.height * 0.075).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
    let font = NSFont.systemFont(ofSize: rect.width * 0.36, weight: .black)
    let text = NSAttributedString(string: "BO", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: rect.width * 0.01])
    let ts = text.size()
    text.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2 + rect.height * 0.04))
    let sub = NSAttributedString(string: "MAC", attributes: [
        .font: NSFont.systemFont(ofSize: rect.width * 0.11, weight: .heavy),
        .foregroundColor: NSColor.white.withAlphaComponent(0.65), .kern: rect.width * 0.03])
    let ss = sub.size()
    sub.draw(at: NSPoint(x: rect.midX - ss.width / 2, y: rect.midY - ts.height / 2 - ss.height * 0.55))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
