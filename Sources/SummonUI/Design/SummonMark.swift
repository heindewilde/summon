import AppKit

/// Summon's mark: a spiral wound clockwise inward, the shape the app icon carries.
///
/// The geometry is deliberately duplicated in `Scripts/make-icon.swift`, which draws
/// the .icns at build time as a standalone script and so cannot import this module.
/// That script's comments carry the reasoning behind the parameters; if the mark is
/// retuned, retune both.
public enum SummonMark {

    /// How the spiral is wound, in pure proportion — no absolute sizes, so one winding
    /// describes the mark at every size it is ever drawn at.
    public struct Winding: Sendable {
        /// Revolutions from the outer mouth to the terminus.
        public var turns: CGFloat
        /// Terminus radius, as a fraction of the mouth's.
        public var innerRatio: CGFloat
        /// Stroke weight at the mouth, as a fraction of the mouth's radius.
        public var widthRatio: CGFloat
        /// How much weight tracks radius: 1 is fully proportional, 0 an even stroke.
        public var falloff: CGFloat
        /// Spacing law: 0 spaces the turns evenly, 1 shrinks each by a fixed fraction.
        public var curl: CGFloat

        public init(turns: CGFloat, innerRatio: CGFloat, widthRatio: CGFloat,
                    falloff: CGFloat, curl: CGFloat) {
            self.turns = turns
            self.innerRatio = innerRatio
            self.widthRatio = widthRatio
            self.falloff = falloff
            self.curl = curl
        }

        /// The app icon's shape, ratio for ratio: `Scripts/make-icon.swift` draws it at
        /// rInner 36, rOuter 256 and maxWidth 72, and 36/256 and 72/256 are what follow.
        /// One shape at every size — only the scale changes.
        public static let standard = Winding(turns: 2.10, innerRatio: 36.0 / 256,
                                             widthRatio: 72.0 / 256,
                                             falloff: 0.55, curl: 0.35)
    }

    // MARK: - Geometry

    /// The mouth's radius in the nominal space the path is built in, before it is fitted
    /// to a frame. Large enough that sampling error stays far below a drawn pixel.
    private static let nominalRadius: CGFloat = 1000

    private static func radius(_ t: CGFloat, _ w: Winding) -> CGFloat {
        let rOuter = nominalRadius, rInner = w.innerRatio * nominalRadius
        let even = rOuter + (rInner - rOuter) * t
        let geometric = rOuter * pow(rInner / rOuter, t)
        return even + (geometric - even) * w.curl
    }

    private static func halfWidth(at radius: CGFloat, _ w: Winding) -> CGFloat {
        w.widthRatio * nominalRadius / 2 * pow(radius / nominalRadius, w.falloff)
    }

    private static func point(_ t: CGFloat, _ w: Winding, sweep: CGFloat,
                              startAngle: CGFloat) -> CGPoint {
        let a = startAngle + t * sweep
        let r = radius(t, w)
        return CGPoint(x: r * cos(a), y: r * sin(a))
    }

    /// The mark as a single closed path, scaled so its ink spans `fill` of `rect`'s
    /// shorter side, and centred there.
    ///
    /// Fitting to the ink rather than to the construction radius matters: a partial
    /// spiral's bounding box falls well short of its full diameter, and by a different
    /// amount for every winding, so nothing but measuring gets the size right.
    ///
    /// The stroke tapers, so the path is built by offsetting a sampled centreline rather
    /// than by stroking — `setLineWidth` is one value for a whole path. The round caps
    /// are woven into the same loop; adding them as separate circles would wind against
    /// the body under the nonzero fill rule and punch holes in it.
    public static func path(in rect: CGRect, winding w: Winding = .standard,
                            fill: CGFloat = 0.84) -> CGPath {
        let sweep = -w.turns * 2 * .pi          // negative: clockwise, winding inward
        let startAngle = CGFloat.pi * 0.72
        let steps = 720, capSteps = 32

        func sample(_ t: CGFloat) -> (p: CGPoint, tangent: CGPoint, normal: CGPoint, half: CGFloat) {
            let p = point(t, w, sweep: sweep, startAngle: startAngle)
            let d: CGFloat = 0.0005
            let a = point(max(0, t - d), w, sweep: sweep, startAngle: startAngle)
            let b = point(min(1, t + d), w, sweep: sweep, startAngle: startAngle)
            var tx = b.x - a.x, ty = b.y - a.y
            let len = max(1e-9, sqrt(tx * tx + ty * ty))
            tx /= len; ty /= len
            return (p, CGPoint(x: tx, y: ty), CGPoint(x: -ty, y: tx),
                    halfWidth(at: radius(t, w), w))
        }

        let samples = (0...steps).map { sample(CGFloat($0) / CGFloat(steps)) }
        let left = samples.map { CGPoint(x: $0.p.x + $0.normal.x * $0.half,
                                         y: $0.p.y + $0.normal.y * $0.half) }
        let right = samples.map { CGPoint(x: $0.p.x - $0.normal.x * $0.half,
                                          y: $0.p.y - $0.normal.y * $0.half) }

        func cap(_ s: (p: CGPoint, tangent: CGPoint, normal: CGPoint, half: CGFloat),
                 outward: CGFloat) -> [CGPoint] {
            (0...capSteps).map { i in
                let phi = CGFloat(i) / CGFloat(capSteps) * .pi
                return CGPoint(x: s.p.x + s.half * (cos(phi) * s.normal.x + outward * sin(phi) * s.tangent.x),
                               y: s.p.y + s.half * (cos(phi) * s.normal.y + outward * sin(phi) * s.tangent.y))
            }
        }

        let loop = left + cap(samples[steps], outward: 1)
            + right.reversed() + cap(samples[0], outward: -1).reversed()
        let raw = CGMutablePath()
        raw.addLines(between: loop)
        raw.closeSubpath()

        // Fit the ink to the frame, centred on the bounding box rather than on the
        // construction centre — the mouth is heavier than the terminus, so the two are
        // not the same point.
        let box = raw.boundingBoxOfPath
        let scale = min(rect.width, rect.height) * fill / max(box.width, box.height)
        var fit = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        return raw.copy(using: &fit) ?? raw
    }

    // MARK: - Menu bar

    /// The mark as a template image, which is what the menu bar needs: macOS ignores a
    /// template's colour and uses only its coverage, so it tints correctly in both
    /// appearances and inverts while the menu is open.
    ///
    /// `fill` puts the ink at about 15pt in the 18pt frame, the size every neighbouring
    /// status item is drawn at.
    @MainActor public static let menuBar: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path(in: rect, fill: 0.84))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
