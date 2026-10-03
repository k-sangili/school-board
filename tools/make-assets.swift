#!/usr/bin/env swift
// Generates the tvOS app icon (layered), App Store icon and Top Shelf images into
// SchoolBoard/Assets.xcassets. Run from the repo root:  swift tools/make-assets.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (matches Theme.swift)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let navyTop = rgb(0x2B3F73), navyBottom = rgb(0x0E1424)
let paper = rgb(0xF4F6FA), chipEmpty = rgb(0xDDE2EA)
let yellow = rgb(0xFFD166), blue = rgb(0x4C9AFF), orange = rgb(0xFFA94D)
let red = rgb(0xFF6B6B), green = rgb(0x3DD68C), ink = rgb(0x1D2430), panel = rgb(0x151A22)

// MARK: - Rendering

/// Draws into a top-left-origin context of `size` points at `scale`, returns PNG data.
func png(_ size: CGSize, scale: CGFloat, opaque: Bool, _ draw: (CGContext, CGSize) -> Void) -> Data {
    let w = Int(size.width * scale), h = Int(size.height * scale)
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx, size)
    NSGraphicsContext.restoreGraphicsState()

    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

func fill(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

func gradient(_ ctx: CGContext, _ size: CGSize, from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // warm glow, top center
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0xFFD166, 0.14), rgb(0xFFD166, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.5, y: 0), startRadius: 0,
                           endCenter: CGPoint(x: size.width * 0.5, y: 0), endRadius: size.height * 0.9, options: [])
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

func text(_ s: String, at p: CGPoint, font: NSFont, color: CGColor) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!]).draw(at: p)
}

// MARK: - App icon layers (5:3 canvas)

func iconBack(_ ctx: CGContext, _ s: CGSize) {
    gradient(ctx, s, from: .zero, to: CGPoint(x: s.width, y: s.height))
}

func cardRect(_ s: CGSize) -> CGRect {
    CGRect(x: s.width * 0.25, y: s.height * 0.17, width: s.width * 0.50, height: s.height * 0.64)
}

func iconMiddle(_ ctx: CGContext, _ s: CGSize) {
    let card = cardRect(s), r = s.height * 0.06
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s.height * 0.025), blur: s.height * 0.06, color: rgb(0x000000, 0.5))
    fill(ctx, card, radius: r, paper)
    ctx.restoreGState()

    // yellow header band
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.clip()
    ctx.setFillColor(yellow)
    ctx.fill(CGRect(x: card.minX, y: card.minY, width: card.width, height: card.height * 0.24))
    ctx.restoreGState()

    // binder rings
    let ringW = card.width * 0.05, ringH = card.height * 0.16
    for fx in [0.3, 0.7] {
        fill(ctx, CGRect(x: card.minX + card.width * fx - ringW / 2, y: card.minY - ringH * 0.45, width: ringW, height: ringH),
             radius: ringW / 2, ink)
    }

    // week grid of homework chips
    let pad = card.width * 0.07, gap = card.width * 0.03
    let body = CGRect(x: card.minX + pad, y: card.minY + card.height * 0.24 + pad * 0.9,
                      width: card.width - 2 * pad, height: card.height * 0.76 - pad * 1.9)
    let cols = 5, rows = 3
    let cw = (body.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let ch = (body.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
    let pattern: [[CGColor]] = [
        [blue, orange, red, blue, green],
        [orange, chipEmpty, blue, red, chipEmpty],
        [chipEmpty, blue, chipEmpty, orange, chipEmpty],
    ]
    for row in 0..<rows {
        for col in 0..<cols {
            let rect = CGRect(x: body.minX + CGFloat(col) * (cw + gap), y: body.minY + CGFloat(row) * (ch + gap), width: cw, height: ch)
            fill(ctx, rect, radius: ch * 0.28, pattern[row][col])
        }
    }
    // "today" column outline
    let today = CGRect(x: body.minX + 3 * (cw + gap) - gap * 0.45, y: body.minY - gap * 0.45,
                       width: cw + gap * 0.9, height: body.height + gap * 0.9)
    ctx.addPath(CGPath(roundedRect: today, cornerWidth: ch * 0.35, cornerHeight: ch * 0.35, transform: nil))
    ctx.setStrokeColor(yellow)
    ctx.setLineWidth(s.height * 0.012)
    ctx.strokePath()
}

func iconFront(_ ctx: CGContext, _ s: CGSize) {
    let card = cardRect(s), d = s.height * 0.30
    let center = CGPoint(x: card.maxX - s.width * 0.01, y: card.maxY - s.height * 0.02)
    let circle = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s.height * 0.02), blur: s.height * 0.05, color: rgb(0x000000, 0.45))
    ctx.setFillColor(green)
    ctx.fillEllipse(in: circle)
    ctx.restoreGState()

    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(s.height * 0.016)
    ctx.strokeEllipse(in: circle.insetBy(dx: s.height * 0.008, dy: s.height * 0.008))

    ctx.setLineWidth(s.height * 0.038)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: center.x - d * 0.22, y: center.y + d * 0.01))
    ctx.addLine(to: CGPoint(x: center.x - d * 0.05, y: center.y + d * 0.17))
    ctx.addLine(to: CGPoint(x: center.x + d * 0.24, y: center.y - d * 0.17))
    ctx.strokePath()
}

// MARK: - Top Shelf (720pt tall; content is laid out on a centered 1920pt stage)

func topShelf(_ ctx: CGContext, _ s: CGSize) {
    gradient(ctx, s, from: CGPoint(x: 0, y: 0), to: CGPoint(x: s.width, y: s.height))
    let x0 = (s.width - 1920) / 2

    text("School Board", at: CGPoint(x: x0 + 150, y: 200), font: rounded(118, .bold), color: rgb(0xFFFFFF))
    text("Homework, tests and school events — at a glance.", at: CGPoint(x: x0 + 156, y: 350),
         font: rounded(40, .medium), color: rgb(0xB8C2D3))
    var lx = x0 + 156
    for (label, color) in [("Homework", blue), ("Test", red), ("Due", orange), ("No school", green)] {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: lx, y: 452, width: 22, height: 22))
        let font = rounded(30, .semibold)
        text(label, at: CGPoint(x: lx + 34, y: 442), font: font, color: rgb(0xE6EAF2))
        lx += 34 + (label as NSString).size(withAttributes: [.font: font]).width + 48
    }

    // Mini week board
    let board = CGRect(x: x0 + 1060, y: 110, width: 720, height: 500)
    let gap: CGFloat = 16
    let colW = (board.width - gap * 4) / 5
    let days = ["MON", "TUE", "WED", "THU", "FRI"]
    let chips: [[CGColor]] = [[blue, orange], [orange, blue, red], [blue], [red, red, orange], [green]]
    for (i, day) in days.enumerated() {
        let col = CGRect(x: board.minX + CGFloat(i) * (colW + gap), y: board.minY, width: colW, height: board.height)
        fill(ctx, col, radius: 22, i == 3 ? rgb(0x1D2430) : rgb(0x151A22, 0.92))
        if i == 3 {
            ctx.addPath(CGPath(roundedRect: col, cornerWidth: 22, cornerHeight: 22, transform: nil))
            ctx.setStrokeColor(yellow); ctx.setLineWidth(5); ctx.strokePath()
        }
        text(day, at: CGPoint(x: col.minX + 18, y: col.minY + 16), font: rounded(24, .heavy),
             color: i == 3 ? yellow : rgb(0x98A2B3))
        var y = col.minY + 66
        for c in chips[i] {
            let chip = CGRect(x: col.minX + 12, y: y, width: colW - 24, height: 92)
            fill(ctx, chip, radius: 14, c.copy(alpha: 0.22)!)
            fill(ctx, CGRect(x: chip.minX + 10, y: chip.minY + 12, width: 6, height: chip.height - 24), radius: 3, c)
            fill(ctx, CGRect(x: chip.minX + 28, y: chip.minY + 22, width: chip.width * 0.42, height: 12), radius: 6, c)
            fill(ctx, CGRect(x: chip.minX + 28, y: chip.minY + 48, width: chip.width * 0.62, height: 14), radius: 7, rgb(0xF1F4F9, 0.85))
            fill(ctx, CGRect(x: chip.minX + 28, y: chip.minY + 68, width: chip.width * 0.40, height: 12), radius: 6, rgb(0xF1F4F9, 0.45))
            y += 104
        }
    }
}

// MARK: - Asset catalog

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SchoolBoard/Assets.xcassets")
let fm = FileManager.default
let info: [String: Any] = ["author": "xcode", "version": 1]

func write(_ json: [String: Any], to dir: URL) {
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: dir.appendingPathComponent("Contents.json"))
}

func imageset(_ dir: URL, base: String, size: CGSize, scales: [CGFloat], opaque: Bool, _ draw: @escaping (CGContext, CGSize) -> Void) {
    var images: [[String: Any]] = []
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for scale in scales {
        let name = scale == 1 ? "\(base).png" : "\(base)@\(Int(scale))x.png"
        try! png(size, scale: scale, opaque: opaque, draw).write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "tv", "scale": "\(Int(scale))x", "filename": name])
    }
    write(["images": images, "info": info], to: dir)
}

func imagestack(_ dir: URL, size: CGSize, scales: [CGFloat]) {
    let layers: [(String, Bool, (CGContext, CGSize) -> Void)] = [("Front", false, iconFront), ("Middle", false, iconMiddle), ("Back", true, iconBack)]
    write(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], to: dir)
    for (name, opaque, draw) in layers {
        let layer = dir.appendingPathComponent("\(name).imagestacklayer")
        write(["info": info], to: layer)
        imageset(layer.appendingPathComponent("Content.imageset"), base: name.lowercased(), size: size, scales: scales, opaque: opaque, draw)
    }
}

try? fm.removeItem(at: root)
write(["info": info], to: root)
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
write([
    "info": info,
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
], to: brand)

imagestack(brand.appendingPathComponent("App Icon.imagestack"), size: CGSize(width: 400, height: 240), scales: [1, 2])
imagestack(brand.appendingPathComponent("App Icon - App Store.imagestack"), size: CGSize(width: 1280, height: 768), scales: [1])
imageset(brand.appendingPathComponent("Top Shelf Image.imageset"), base: "topshelf", size: CGSize(width: 1920, height: 720), scales: [1, 2], opaque: true, topShelf)
imageset(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), base: "topshelf-wide", size: CGSize(width: 2320, height: 720), scales: [1, 2], opaque: true, topShelf)

// Flattened previews for docs / quick review
let previews = URL(fileURLWithPath: "docs")
try? fm.createDirectory(at: previews, withIntermediateDirectories: true)
try! png(CGSize(width: 800, height: 480), scale: 1, opaque: true) { ctx, s in iconBack(ctx, s); iconMiddle(ctx, s); iconFront(ctx, s) }
    .write(to: previews.appendingPathComponent("app-icon.png"))
try! png(CGSize(width: 1920, height: 720), scale: 1, opaque: true, topShelf).write(to: previews.appendingPathComponent("top-shelf.png"))
print("Wrote \(root.path)")
