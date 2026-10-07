// Renders the app icon and the GitHub social preview.
// Usage: swift design/render-artwork.swift <output-folder>
import AppKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func save(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
    print("wrote", name)
}

/// The mark: a red record ring with stem bars in mixer scribble colors, centered in `rect`.
func drawMark(_ ctx: CGContext, in rect: CGRect) {
    let s = rect.width
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = s * 0.36
    let ringWidth = s * 0.075

    // Soft red glow behind the ring.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: rgb(0xFF3B30, 0.55))
    ctx.setStrokeColor(rgb(0xFF453A))
    ctx.setLineWidth(ringWidth)
    ctx.strokeEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
    ctx.restoreGState()

    // Stem bars inside the ring: one per Source, in X-Air scribble colors.
    let colors: [UInt32] = [0xFF453A, 0xFFD60A, 0x30D158, 0x0A84FF, 0x64D2FF, 0xBF5AF2, 0xF2F2F7]
    let heights: [CGFloat] = [0.42, 0.68, 0.88, 1.0, 0.80, 0.58, 0.36]
    let inner = ringRadius - ringWidth / 2 - s * 0.055
    let barWidth = inner * 2 / (CGFloat(colors.count) * 1.55)
    let gap = barWidth * 0.55
    let total = CGFloat(colors.count) * barWidth + CGFloat(colors.count - 1) * gap
    var x = center.x - total / 2
    for (color, h) in zip(colors, heights) {
        let height = inner * 1.55 * h
        let bar = CGRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
        ctx.setFillColor(rgb(color))
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }
}

func drawBackground(_ ctx: CGContext, _ rect: CGRect) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x2A2E37), rgb(0x111318)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

// App icon: full-bleed square, no transparency (the OS applies the mask).
let icon = context(1024, 1024)
drawBackground(icon, CGRect(x: 0, y: 0, width: 1024, height: 1024))
drawMark(icon, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
save(icon, "AppIcon-1024.png")

// macOS icon: macOS doesn't mask, so draw the rounded tile with the standard margin (824 of 1024).
let mac = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let macTile = CGRect(x: 100, y: 100, width: 824, height: 824)
mac.saveGState()
mac.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
mac.addPath(CGPath(roundedRect: macTile, cornerWidth: 185, cornerHeight: 185, transform: nil))
mac.setFillColor(rgb(0x1B1E25))
mac.fillPath()
mac.restoreGState()
mac.saveGState()
mac.addPath(CGPath(roundedRect: macTile, cornerWidth: 185, cornerHeight: 185, transform: nil))
mac.clip()
drawBackground(mac, macTile)
drawMark(mac, in: macTile)
mac.restoreGState()
save(mac, "AppIcon-mac-1024.png")

// Social preview: 1280 x 640 (GitHub, Open Graph).
let card = context(1280, 640)
drawBackground(card, CGRect(x: 0, y: 0, width: 1280, height: 640))
let tile = CGRect(x: 96, y: 160, width: 320, height: 320)
card.saveGState()
card.addPath(CGPath(roundedRect: tile, cornerWidth: 72, cornerHeight: 72, transform: nil))
card.clip()
card.setFillColor(rgb(0x1B1E25))
card.fill(tile)
drawMark(card, in: tile)
card.restoreGState()
card.setStrokeColor(rgb(0xFFFFFF, 0.08))
card.setLineWidth(2)
card.addPath(CGPath(roundedRect: tile, cornerWidth: 72, cornerHeight: 72, transform: nil))
card.strokePath()

NSGraphicsContext.current = NSGraphicsContext(cgContext: card, flipped: false)
func text(_ string: String, _ font: NSFont, _ color: NSColor, _ origin: CGPoint) {
    NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: origin)
}
text("ShowRecorder", .systemFont(ofSize: 76, weight: .bold), .white, CGPoint(x: 480, y: 372))
text("Record every channel of your mixer", .systemFont(ofSize: 34, weight: .medium), NSColor(white: 0.86, alpha: 1), CGPoint(x: 482, y: 300))
text("from an iPhone, iPad or Mac. No laptop.", .systemFont(ofSize: 34, weight: .medium), NSColor(white: 0.86, alpha: 1), CGPoint(x: 482, y: 256))
text("Named stems  ·  Broadcast WAV  ·  Reaper project", .systemFont(ofSize: 24, weight: .regular), NSColor(white: 0.6, alpha: 1), CGPoint(x: 482, y: 190))
save(card, "social-preview.png")
