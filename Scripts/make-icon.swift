// Draws the Summon app icon with CoreGraphics and writes the PNG set for iconutil.
// No external tooling required. Run: swift Scripts/make-icon.swift <outDir>
import AppKit
import CoreGraphics
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./.build/icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Identity colours (mirrors SummonUI.DesignTokens)
let violetDeep = CGColor(red: 0.32, green: 0.22, blue: 0.72, alpha: 1)
let violetLight = CGColor(red: 0.52, green: 0.38, blue: 0.96, alpha: 1)
let amber = CGColor(red: 1.00, green: 0.74, blue: 0.26, alpha: 1)
let amberHot = CGColor(red: 1.00, green: 0.60, blue: 0.20, alpha: 1)

func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A four-point sparkle — the "summoned" spark.
func sparklePath(at c: CGPoint, r: CGFloat, waist: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let w = r * waist
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addCurve(to: CGPoint(x: c.x + r, y: c.y),
               control1: CGPoint(x: c.x + w, y: c.y + w), control2: CGPoint(x: c.x + w, y: c.y + w))
    p.addCurve(to: CGPoint(x: c.x, y: c.y - r),
               control1: CGPoint(x: c.x + w, y: c.y - w), control2: CGPoint(x: c.x + w, y: c.y - w))
    p.addCurve(to: CGPoint(x: c.x - r, y: c.y),
               control1: CGPoint(x: c.x - w, y: c.y - w), control2: CGPoint(x: c.x - w, y: c.y - w))
    p.addCurve(to: CGPoint(x: c.x, y: c.y + r),
               control1: CGPoint(x: c.x - w, y: c.y + w), control2: CGPoint(x: c.x - w, y: c.y + w))
    p.closeSubpath()
    return p
}

func drawIcon(size: CGFloat) -> CGImage? {
    let s = size / 1024.0
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Rounded-square app shape, standard macOS proportions.
    let body = CGRect(x: 100 * s, y: 90 * s, width: 824 * s, height: 824 * s)
    let shape = squirclePath(rect: body, radius: 185 * s)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s,
                  color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape); ctx.setFillColor(violetDeep); ctx.fillPath()
    ctx.restoreGState()

    // Violet gradient body.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [violetLight, violetDeep] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Soft top-light sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(sheen,
                           startCenter: CGPoint(x: body.midX, y: body.maxY), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.maxY), endRadius: 620 * s,
                           options: [])
    ctx.restoreGState()

    // Two stacked cards: the library. Back card recedes, front card is crisp.
    let cardW = 430 * s, cardH = 300 * s
    let cx = body.midX - 34 * s, cy = body.midY - 66 * s

    ctx.saveGState()
    let back = CGRect(x: cx - cardW / 2 + 34 * s, y: cy - cardH / 2 + 62 * s, width: cardW, height: cardH)
    ctx.addPath(squirclePath(rect: back, radius: 52 * s))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.30))
    ctx.fillPath()

    let mid = CGRect(x: cx - cardW / 2 + 17 * s, y: cy - cardH / 2 + 31 * s, width: cardW, height: cardH)
    ctx.addPath(squirclePath(rect: mid, radius: 52 * s))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
    ctx.fillPath()

    let front = CGRect(x: cx - cardW / 2, y: cy - cardH / 2, width: cardW, height: cardH)
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 24 * s,
                  color: CGColor(red: 0.15, green: 0.08, blue: 0.35, alpha: 0.45))
    ctx.addPath(squirclePath(rect: front, radius: 52 * s))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.97))
    ctx.fillPath()
    ctx.restoreGState()

    // Content lines on the front card.
    ctx.setFillColor(CGColor(red: 0.42, green: 0.34, blue: 0.62, alpha: 0.55))
    for (i, w) in [0.62, 0.80, 0.44].enumerated() {
        let lh = 26 * s
        let y = front.maxY - 84 * s - CGFloat(i) * 62 * s
        let r = CGRect(x: front.minX + 52 * s, y: y, width: front.width * CGFloat(w) - 40 * s, height: lh)
        ctx.addPath(squirclePath(rect: r, radius: lh / 2))
        ctx.fillPath()
    }

    // The spark being summoned, rising from the stack.
    let sc = CGPoint(x: body.maxX - 216 * s, y: body.maxY - 214 * s)
    let sparkR: CGFloat = 158 * s
    let spark = sparklePath(at: sc, r: sparkR, waist: 0.14)

    // Warm bloom on the violet field behind the spark.
    ctx.saveGState()
    let bloom = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [amberHot.copy(alpha: 0.55)!, amberHot.copy(alpha: 0)!] as CFArray,
                           locations: [0, 1])!
    ctx.addPath(shape); ctx.clip()
    ctx.drawRadialGradient(bloom, startCenter: sc, startRadius: 0,
                           endCenter: sc, endRadius: 300 * s, options: [])
    ctx.restoreGState()

    // Spark body: solid pass carries the shadow, gradient pass carries the colour.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40 * s, color: amberHot.copy(alpha: 0.9)!)
    ctx.addPath(spark); ctx.setFillColor(amber); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(spark); ctx.clip()
    let sg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                        colors: [CGColor(red: 1, green: 0.90, blue: 0.62, alpha: 1), amberHot] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(sg, start: CGPoint(x: sc.x, y: sc.y + sparkR),
                           end: CGPoint(x: sc.x, y: sc.y - sparkR), options: [])
    ctx.restoreGState()

    // A small companion spark, on the violet field, for diagonal balance.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22 * s, color: amberHot.copy(alpha: 0.7)!)
    ctx.addPath(sparklePath(at: CGPoint(x: body.minX + 168 * s, y: body.maxY - 168 * s),
                            r: 52 * s, waist: 0.14))
    ctx.setFillColor(amber.copy(alpha: 0.95)!)
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

// iconset sizes
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                           (256, 1), (256, 2), (512, 1), (512, 2)]
for (pt, scale) in sizes {
    let px = pt * scale
    guard let img = drawIcon(size: CGFloat(px)) else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    write(img, to: "\(outDir)/\(name)")
}
if let big = drawIcon(size: 1024) { write(big, to: "\(outDir)/../summon-icon-1024.png") }
print("Icon set written to \(outDir)")
