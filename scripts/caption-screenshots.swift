#!/usr/bin/env swift
// Captions App Store screenshots in the style of the iPhone 1.2 set (docs/images/app-store-iphone-1.2, #1233):
// a dark gradient, a bold headline (white, then coral), an optional gray "With Pro" line, and the screenshot in a
// thin rounded frame that runs off the bottom edge. The iPhone set's own compositing script wasn't kept, so these
// numbers were measured from its PNGs (#1259); the iPad layout scales them up.
//
//   swift scripts/caption-screenshots.swift <device> <raw folder> <output folder>
//
// <device> is `ipad13` (2064 × 2752) or `iphone69` (1320 × 2868). <raw folder> holds the uncaptioned Simulator
// screenshots named as in `shots` below (01.png … 06.png); <output folder> gets the captioned PNGs, RGB with no alpha.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shot {
    let raw: String
    let output: String
    /// Headline lines: (text, coral?).
    let lines: [(String, Bool)]
    let withPro: Bool
}

/// The iPhone 1.2 set's order and captions (docs/images/app-store-iphone-1.2/README.md).
let shots: [Shot] = [
    Shot(raw: "01.png", output: "01-every-channel.png",
         lines: [("Every channel of", false), ("your mixer.", false), ("Its own WAV.", true)], withPro: false),
    Shot(raw: "02.png", output: "02-any-usb-mixer-free.png",
         lines: [("Any class-compliant", false), ("USB mixer.", false), ("Free.", true)], withPro: false),
    Shot(raw: "03.png", output: "03-named-from-mixer.png",
         lines: [("XR18 or X32?", false), ("Files named from", true), ("the mixer.", true)], withPro: true),
    Shot(raw: "04.png", output: "04-second-copy-drive.png",
         lines: [("A second copy", false), ("on a USB drive.", true)], withPro: true),
    Shot(raw: "05.png", output: "05-ready-for-daw.png",
         lines: [("Ready for your DAW.", false), ("Named files and Markers.", true)], withPro: true),
    Shot(raw: "06.png", output: "06-pro-one-purchase.png",
         lines: [("Pro is one purchase.", false), ("No subscription.", true)], withPro: false),
]

/// One canvas size's layout, in pixels. `iphone69` is as measured from the iPhone set; `ipad13` scales its type by
/// `typeScale` and fits the iPad's wider screen.
struct Layout {
    let width: Int
    let height: Int
    let fontSize: CGFloat
    let kern: CGFloat
    let firstBaseline: CGFloat
    let lineSpacing: CGFloat
    let subFontSize: CGFloat
    let subGap: CGFloat
    let frameTop: CGFloat
    let frameWidth: CGFloat
    let border: CGFloat
    let outerRadius: CGFloat
    let shadowBlur: CGFloat

    static let iphone69 = Layout(
        width: 1320, height: 2868, fontSize: 100, kern: -1.0, firstBaseline: 247, lineSpacing: 120,
        subFontSize: 50, subGap: 95, frameTop: 697, frameWidth: 1062, border: 6, outerRadius: 125, shadowBlur: 60)

    static let ipad13: Layout = {
        let k: CGFloat = 1.25
        let p = iphone69
        return Layout(
            width: 2064, height: 2752, fontSize: p.fontSize * k, kern: p.kern * k, firstBaseline: p.firstBaseline * k,
            lineSpacing: p.lineSpacing * k, subFontSize: p.subFontSize * k, subGap: p.subGap * k,
            frameTop: p.frameTop * k, frameWidth: 1480, border: 8, outerRadius: 64, shadowBlur: p.shadowBlur * k)
    }()
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let backgroundTop = rgb(42, 46, 55)      // #2A2E37
let backgroundBottom = rgb(17, 19, 24)   // #111318
let white = rgb(247, 247, 250)           // #F7F7FA
let coral = rgb(255, 115, 107)           // #FF736B
let gray = rgb(189, 191, 199)            // #BDBFC7
let frameColor = rgb(58, 62, 71)         // #3A3E47

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("can't read \(url.path)")
    }
    return image
}

/// Draws `text` centered on `x` with its baseline at `baseline` (top-left origin; the context is flipped).
func drawCentered(_ text: String, in ctx: CGContext, x: CGFloat, baseline: CGFloat, size: CGFloat, weight: NSFont.Weight,
                  kern: CGFloat, color: CGColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: kern, .foregroundColor: NSColor(cgColor: color)!]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    // The width without the kern after the last glyph, so the line is truly centered.
    let width = CTLineGetTypographicBounds(line, nil, nil, nil) - Double(kern)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: x - CGFloat(width) / 2, y: baseline)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func compose(_ shot: Shot, layout l: Layout, raw: CGImage) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: l.width, height: l.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("context") }
    let w = CGFloat(l.width), h = CGFloat(l.height)
    // Top-left origin, like the measurements.
    ctx.translateBy(x: 0, y: h)
    ctx.scaleBy(x: 1, y: -1)

    let gradient = CGGradient(colorsSpace: space, colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])

    var baseline = l.firstBaseline
    for (text, isCoral) in shot.lines {
        drawCentered(text, in: ctx, x: w / 2, baseline: baseline, size: l.fontSize, weight: .bold, kern: l.kern,
                     color: isCoral ? coral : white)
        baseline += l.lineSpacing
    }
    if shot.withPro {
        drawCentered("With Pro", in: ctx, x: w / 2, baseline: baseline - l.lineSpacing + l.subGap, size: l.subFontSize,
                     weight: .bold, kern: l.kern / 2, color: gray)
    }

    // The frame: a rounded rect from `frameTop` to past the bottom edge, with a soft shadow, a thin border and the
    // screenshot inside, scaled to the frame's inner width.
    let frameX = (w - l.frameWidth) / 2
    let screenWidth = l.frameWidth - 2 * l.border
    let scale = screenWidth / CGFloat(raw.width)
    let screenHeight = CGFloat(raw.height) * scale
    let outer = CGRect(x: frameX, y: l.frameTop, width: l.frameWidth, height: screenHeight + 2 * l.border)
    let inner = outer.insetBy(dx: l.border, dy: l.border)
    let outerPath = CGPath(roundedRect: outer, cornerWidth: l.outerRadius, cornerHeight: l.outerRadius, transform: nil)
    let innerRadius = l.outerRadius - l.border
    let innerPath = CGPath(roundedRect: inner, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -l.shadowBlur / 3), blur: l.shadowBlur, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.addPath(outerPath)
    ctx.setFillColor(frameColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(innerPath)
    ctx.clip()
    ctx.interpolationQuality = .high
    // Undo the flip for the image, so it draws upright.
    ctx.translateBy(x: inner.minX, y: inner.minY + screenHeight)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(raw, in: CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("can't write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("can't write \(url.path)") }
}

let args = CommandLine.arguments
guard args.count == 4, let layout = ["ipad13": Layout.ipad13, "iphone69": Layout.iphone69][args[1]] else {
    FileHandle.standardError.write("usage: caption-screenshots.swift ipad13|iphone69 <raw folder> <output folder>\n".data(using: .utf8)!)
    exit(2)
}
let rawFolder = URL(fileURLWithPath: args[2], isDirectory: true)
let outFolder = URL(fileURLWithPath: args[3], isDirectory: true)
try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
for shot in shots {
    let rawURL = rawFolder.appending(path: shot.raw)
    guard FileManager.default.fileExists(atPath: rawURL.path) else {
        print("skip \(shot.output): no \(shot.raw)")
        continue
    }
    writePNG(compose(shot, layout: layout, raw: loadImage(rawURL)), to: outFolder.appending(path: shot.output))
    print("wrote \(shot.output)")
}
