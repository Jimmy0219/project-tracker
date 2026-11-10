// 產生 App 圖示：swiftc scripts/make-icon.swift -o build/make-icon && build/make-icon <輸出.iconset>
// 圖案：藍紫漸層圓角方塊上，三列待辦（兩列已勾選、一列未完成）加一條進度條。
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024  // 以 1024 設計稿為基準縮放
    ctx.scaleBy(x: s, y: s)

    // 背景：符合 macOS 圖示格線（824×824，置中），含柔和陰影
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x3A45E0).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x5B8CFF), ending: color(0x3B32D4))!.draw(in: tilePath, angle: -90)

    // 頂部高光
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.18), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 三列待辦（y 由上而下）
    let rows: [(y: CGFloat, done: Bool, length: CGFloat)] = [
        (690, true, 330), (545, true, 260), (400, false, 300),
    ]
    for row in rows {
        let circle = NSRect(x: 230, y: row.y - 48, width: 96, height: 96)
        if row.done {
            color(0x4CE0A0).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: circle.minX + 25, y: circle.midY + 2))
            check.line(to: NSPoint(x: circle.minX + 42, y: circle.midY - 16))
            check.line(to: NSPoint(x: circle.minX + 72, y: circle.midY + 18))
            check.lineWidth = 13
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 7, dy: 7))
            ring.lineWidth = 14
            NSColor.white.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }
        let bar = NSRect(x: 370, y: row.y - 22, width: row.length, height: 44)
        NSColor.white.withAlphaComponent(row.done ? 0.55 : 0.95).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 22, yRadius: 22).fill()
    }

    // 進度條
    let track = NSRect(x: 230, y: 228, width: 564, height: 40)
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: track, xRadius: 20, yRadius: 20).fill()
    let fill = NSRect(x: track.minX, y: track.minY, width: track.width * 0.66, height: track.height)
    color(0x4CE0A0).setFill()
    NSBezierPath(roundedRect: fill, xRadius: 20, yRadius: 20).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = drawIcon(size: base * scale).representation(using: .png, properties: [:])!
        try data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    }
}
print("✓ \(out)")
