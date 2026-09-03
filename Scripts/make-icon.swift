// Draws the Summon app icon with CoreGraphics and writes the PNG set for iconutil.
// No external tooling required. Run: swift Scripts/make-icon.swift <outDir>
//
// The mark is a single tapered spiral — a vortex, the opening a summoned thing
// comes through. One stroke, one hue, on a near-black tile. Everything else was
// cut: the card stack, the amber sparks, the sheen. An app icon has to survive
// being 16 points wide in a menu bar, and five elements do not.
import AppKit
import CoreGraphics
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./.build/icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Identity colours

// The tile: near-black, barely graded, so the glyph is the only thing that glows.
let tileTop = CGColor(red: 0.114, green: 0.110, blue: 0.141, alpha: 1)   // #1D1C24
let tileBottom = CGColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1) // #0B0B0F

// The glyph. `violet` is SummonUI's own on-dark accent — Colors.folderColor("violet"),
// dark variant — so the icon and the app's violet are literally the same colour.
let violet = CGColor(red: 0.64, green: 0.55, blue: 1.00, alpha: 1)
let violetBright = CGColor(red: 0.84, green: 0.80, blue: 1.00, alpha: 1)
let violetDeep = CGColor(red: 0.42, green: 0.30, blue: 0.92, alpha: 1)

func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: - The spiral

/// Radius at `t`, blending the two spiral families. At `curl` 0 the radius falls
/// linearly and the turns are evenly spaced — Archimedean, the spiral as it is drawn
/// by hand. At 1 it decays geometrically, every turn a fixed fraction of the last —
/// logarithmic, which winds tighter for free but reads as a shell. Partway between,
/// the coil tightens a little as it goes in without the shell's lopsided proportions.
private func spiralRadius(rInner: CGFloat, rOuter: CGFloat, t: CGFloat, curl: CGFloat) -> CGFloat {
    let even = rOuter + (rInner - rOuter) * t
    let geometric = rOuter * pow(rInner / rOuter, t)
    return even + (geometric - even) * curl
}

/// Centreline: t = 0 is the wide outer mouth, t = 1 the terminus curled into the eye.
private func spiralPoint(center: CGPoint, rInner: CGFloat, rOuter: CGFloat,
                         sweep: CGFloat, startAngle: CGFloat, t: CGFloat,
                         curl: CGFloat) -> CGPoint {
    let a = startAngle + t * sweep
    let r = spiralRadius(rInner: rInner, rOuter: rOuter, t: t, curl: curl)
    return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
}

/// The stroke's half-width. `falloff` sets how much weight tracks radius: 1 is fully
/// proportional (self-similar, and the reason the shell version tapered so hard), 0 is
/// a perfectly even stroke. A little falloff thins the inner coil just enough to keep
/// it clear of its neighbour without the taper becoming the thing you notice.
private func spiralHalfWidth(radius: CGFloat, rOuter: CGFloat, maxWidth: CGFloat,
                             falloff: CGFloat) -> CGFloat {
    maxWidth / 2 * pow(radius / rOuter, falloff)
}

/// Outlines the tapered spiral as a single closed polygon. Sampling the centreline
/// and offsetting along the normal is the only way to vary stroke weight in
/// CoreGraphics — `setLineWidth` is constant for the whole path. The round caps are
/// woven into the same loop rather than added as separate circles: overlapping
/// subpaths wind against each other under the nonzero rule and punch holes.
func spiralPath(center: CGPoint, rInner: CGFloat, rOuter: CGFloat, turns: CGFloat,
                startAngle: CGFloat, maxWidth: CGFloat, falloff: CGFloat,
                curl: CGFloat) -> CGPath {
    // Negative: the stroke winds clockwise inward, matching the 🌀 the README opens with.
    let sweep = -turns * 2 * .pi
    let steps = 900
    let capSteps = 48

    func sample(_ t: CGFloat) -> (p: CGPoint, tangent: CGPoint, normal: CGPoint, half: CGFloat) {
        let p = spiralPoint(center: center, rInner: rInner, rOuter: rOuter,
                            sweep: sweep, startAngle: startAngle, t: t, curl: curl)
        // Tangent by central difference; the ends fall back to a one-sided step.
        let d: CGFloat = 0.0005
        let a = spiralPoint(center: center, rInner: rInner, rOuter: rOuter,
                            sweep: sweep, startAngle: startAngle, t: max(0, t - d), curl: curl)
        let b = spiralPoint(center: center, rInner: rInner, rOuter: rOuter,
                            sweep: sweep, startAngle: startAngle, t: min(1, t + d), curl: curl)
        var tx = b.x - a.x, ty = b.y - a.y
        let len = max(1e-9, sqrt(tx * tx + ty * ty))
        tx /= len; ty /= len
        return (p, CGPoint(x: tx, y: ty), CGPoint(x: -ty, y: tx),
                spiralHalfWidth(radius: spiralRadius(rInner: rInner, rOuter: rOuter, t: t, curl: curl),
                                rOuter: rOuter, maxWidth: maxWidth, falloff: falloff))
    }

    let samples = (0...steps).map { sample(CGFloat($0) / CGFloat(steps)) }
    let left = samples.map { CGPoint(x: $0.p.x + $0.normal.x * $0.half,
                                     y: $0.p.y + $0.normal.y * $0.half) }
    let right = samples.map { CGPoint(x: $0.p.x - $0.normal.x * $0.half,
                                      y: $0.p.y - $0.normal.y * $0.half) }

    /// Half-disc from the left offset round to the right offset, bulging along `dir`.
    func cap(_ s: (p: CGPoint, tangent: CGPoint, normal: CGPoint, half: CGFloat),
             outward: CGFloat) -> [CGPoint] {
        (0...capSteps).map { i in
            let phi = CGFloat(i) / CGFloat(capSteps) * .pi
            return CGPoint(x: s.p.x + s.half * (cos(phi) * s.normal.x + outward * sin(phi) * s.tangent.x),
                           y: s.p.y + s.half * (cos(phi) * s.normal.y + outward * sin(phi) * s.tangent.y))
        }
    }

    let loop = left + cap(samples[steps], outward: 1) + right.reversed() + cap(samples[0], outward: -1).reversed()
    let p = CGMutablePath()
    p.addLines(between: loop)
    p.closeSubpath()

    // Optically centre on the ink. A spiral's construction centre is not its visual
    // one — the gap pulls all the mass to the closed side — so re-centre on the
    // bounding box. Doing it here means retuning the radii can't knock it off centre.
    let box = p.boundingBoxOfPath
    var shift = CGAffineTransform(translationX: center.x - box.midX, y: center.y - box.midY)
    return p.copy(using: &shift) ?? p
}

func drawIcon(size: CGFloat) -> CGImage? {
    let s = size / 1024.0
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Rounded-square app shape, standard macOS proportions.
    let body = CGRect(x: 100 * s, y: 90 * s, width: 824 * s, height: 824 * s)
    let shape = squirclePath(rect: body, radius: 185 * s)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(tileBottom); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()

    // Near-black tile, top-lit just enough to have a direction.
    let tile = CGGradient(colorsSpace: space, colors: [tileTop, tileBottom] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(tile, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    let center = CGPoint(x: body.midX, y: body.midY)
    // The pitch, (rOuter - rInner) / turns, is the budget every coil spends: it has to
    // cover maxWidth plus a visible gap. Winding tighter means a thinner stroke, not a
    // closer one — `turns` and `maxWidth` move against each other, always. `falloff`
    // and `curl` then set how much of the shell's character to keep; both sit near a
    // third, which is bolder and more tapered than a drafted spiral but well short of
    // the nautilus that full proportional weight produces.
    let spiral = spiralPath(center: center, rInner: 36 * s, rOuter: 256 * s,
                            turns: 2.10, startAngle: .pi * 0.72,
                            maxWidth: 72 * s, falloff: 0.55, curl: 0.35)

    // Violet bloom on the tile behind the glyph, so the mark looks lit from within
    // rather than pasted on. Drawn inside the clip so it never spills past the edge.
    let bloom = CGGradient(colorsSpace: space,
                           colors: [violetDeep.copy(alpha: 0.06)!,
                                    violetDeep.copy(alpha: 0.26)!,
                                    violetDeep.copy(alpha: 0)!] as CFArray,
                           locations: [0, 0.52, 1])!
    ctx.drawRadialGradient(bloom, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: 400 * s, options: [])

    // Two shadow passes: a wide halo, then a tight one that sharpens the edge.
    for (blur, alpha) in [(64 * s, 0.50), (22 * s, 0.60)] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blur, color: violet.copy(alpha: alpha)!)
        ctx.addPath(spiral)
        ctx.setFillColor(violet)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // The glyph itself, lit from the upper left so the mouth reads hottest.
    ctx.saveGState()
    ctx.addPath(spiral)
    ctx.clip()
    let sg = CGGradient(colorsSpace: space,
                        colors: [violetBright, violet, violetDeep] as CFArray,
                        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(sg, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    // Hairline rim: the thing that makes a dark tile look cut rather than printed.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(3 * s)
    ctx.strokePath()

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
