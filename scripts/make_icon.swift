// Renders the app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift scripts/make_icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.24, alpha: 1),
                        NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1)])!.draw(in: plate, angle: -90)

    let c = NSPoint(x: s / 2, y: s / 2)
    let rings: [(inner: CGFloat, outer: CGFloat, parts: [CGFloat])] = [
        (0.15, 0.24, [0.34, 0.22, 0.18, 0.14, 0.12]),
        (0.25, 0.33, [0.20, 0.14, 0.12, 0.10, 0.09, 0.08, 0.07]),
    ]
    for (ri, ring) in rings.enumerated() {
        var start: CGFloat = 0
        for part in ring.parts {
            let gap: CGFloat = 0.008
            let a0 = 90 - (start + gap) * 360
            let a1 = 90 - (start + part - gap) * 360
            let p = NSBezierPath()
            p.appendArc(withCenter: c, radius: s * ring.outer, startAngle: a0, endAngle: a1, clockwise: true)
            p.appendArc(withCenter: c, radius: s * ring.inner, startAngle: a1, endAngle: a0, clockwise: false)
            p.close()
            NSColor(hue: start + part / 2, saturation: 0.66 - CGFloat(ri) * 0.08,
                    brightness: 1.0 - CGFloat(ri) * 0.12, alpha: 1).setFill()
            p.fill()
            start += part
        }
    }
    let dot = NSBezierPath(ovalIn: NSRect(x: c.x - s * 0.10, y: c.y - s * 0.10, width: s * 0.20, height: s * 0.20))
    NSGradient(colors: [NSColor(red: 0.62, green: 0.40, blue: 1, alpha: 1),
                        NSColor(red: 0.33, green: 0.56, blue: 1, alpha: 1)])!.draw(in: dot, angle: 45)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
