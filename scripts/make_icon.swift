import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Forge app icon (light, dark, tinted) as 1024x1024 PNGs.
// Usage: swift make_icon.swift <output dir>

let size = 1024
let outDir = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

enum Variant { case light, dark, tinted }

func glyphPath() -> CGPath {
    // A dumbbell built from rounded rectangles, centred on the origin.
    let path = CGMutablePath()
    let bar = CGRect(x: -250, y: -26, width: 500, height: 52)
    path.addRoundedRect(in: bar, cornerWidth: 26, cornerHeight: 26)
    let plates: [(x: CGFloat, w: CGFloat, h: CGFloat)] = [
        (-300, 78, 400), (-382, 64, 290), (222, 78, 400), (318, 64, 290),
    ]
    for p in plates {
        let rect = CGRect(x: p.x, y: -p.h / 2, width: p.w, height: p.h)
        path.addRoundedRect(in: rect, cornerWidth: 30, cornerHeight: 30)
    }
    return path
}

func sparkPath() -> CGPath {
    // A four-point spark used as the "forge" accent.
    let path = CGMutablePath()
    let r: CGFloat = 70, inner: CGFloat = 16
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let radius = i % 2 == 0 ? r : inner
        let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func render(_ variant: Variant, to file: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background
    switch variant {
    case .light:
        let g = CGGradient(colorsSpace: space, colors: [
            color(1.0, 0.74, 0.24), color(1.0, 0.42, 0.10), color(0.93, 0.20, 0.17),
        ] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
    case .dark:
        let g = CGGradient(colorsSpace: space, colors: [
            color(0.16, 0.10, 0.08), color(0.05, 0.04, 0.04),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])
        // warm glow behind the glyph
        let glow = CGGradient(colorsSpace: space, colors: [color(1.0, 0.42, 0.10, 0.35), color(1.0, 0.42, 0.10, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 520, options: [])
    case .tinted:
        ctx.setFillColor(color(0, 0, 0))
        ctx.fill(full)
    }

    // Glyph
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 500)
    ctx.rotate(by: .pi / 4.6)
    let glyph = glyphPath()
    switch variant {
    case .light:
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0.45, 0.08, 0.02, 0.45))
        ctx.addPath(glyph)
        ctx.setFillColor(color(1, 1, 1))
        ctx.fillPath()
    case .dark:
        ctx.addPath(glyph)
        ctx.clip()
        let g = CGGradient(colorsSpace: space, colors: [
            color(1.0, 0.78, 0.30), color(1.0, 0.45, 0.12), color(0.95, 0.22, 0.18),
        ] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: -400, y: 220), end: CGPoint(x: 400, y: -220), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    case .tinted:
        ctx.addPath(glyph)
        ctx.setFillColor(color(1, 1, 1))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Spark accent
    ctx.saveGState()
    ctx.translateBy(x: 270, y: 760)
    ctx.addPath(sparkPath())
    switch variant {
    case .light: ctx.setFillColor(color(1, 1, 1, 0.95))
    case .dark: ctx.setFillColor(color(1.0, 0.80, 0.35))
    case .tinted: ctx.setFillColor(color(0.85, 0.85, 0.85))
    }
    ctx.fillPath()
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

render(.light, to: "AppIcon.png")
render(.dark, to: "AppIcon-Dark.png")
render(.tinted, to: "AppIcon-Tinted.png")
print("icons written to \(outDir)")
