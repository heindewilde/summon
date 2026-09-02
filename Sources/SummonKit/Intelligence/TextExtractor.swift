import AppKit
import Foundation
import PDFKit
import Vision

/// Pulls readable text out of images and documents so their *contents* are findable,
/// not just their filenames. Runs off the main actor; results are plain strings.
public struct TextExtractor: Sendable {

    public static let maxPDFPages = 30
    public static let maxCharacters = 40_000

    /// Best-effort extraction for any imported file.
    public static func extract(from url: URL, kind: ItemKind) async -> String {
        switch kind {
        case .image:
            guard let data = try? Data(contentsOf: url) else { return "" }
            return await ocr(imageData: data)
        case .document:
            return await documentText(url: url)
        case .file, .text, .richText:
            return ""
        }
    }

    // MARK: - Images

    public static func ocr(imageData: Data) async -> String {
        await Task.detached(priority: .utility) {
            guard let image = NSImage(data: imageData),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return "" }
            return recognizeText(in: cgImage)
        }.value
    }

    private static func recognizeText(in cgImage: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Dutch alongside English, since this library will hold both.
        request.recognitionLanguages = ["en-US", "nl-NL"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.ai.warning("OCR failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(maxCharacters))
    }

    // MARK: - Documents

    public static func documentText(url: URL) async -> String {
        await Task.detached(priority: .utility) {
            if url.pathExtension.lowercased() == "pdf" {
                return pdfText(url: url)
            }
            // Plain and rich text documents read directly.
            if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
                return String(attributed.string.prefix(maxCharacters))
            }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return String(text.prefix(maxCharacters))
            }
            return ""
        }.value
    }

    static func pdfText(url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var collected = ""
        let pages = min(document.pageCount, maxPDFPages)

        for i in 0..<pages {
            guard let page = document.page(at: i) else { continue }
            if let text = page.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                collected += text + "\n"
            } else {
                // A scanned page has no text layer, so render it and read it with Vision.
                collected += ocrPage(page) + "\n"
            }
            if collected.count > maxCharacters { break }
        }
        return String(collected.prefix(maxCharacters))
    }

    private static func ocrPage(_ page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return "" }
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return "" }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return "" }
        return recognizeText(in: cgImage)
    }

    // MARK: - Thumbnails

    /// A PNG preview for the results list and grid.
    public static func thumbnail(for url: URL, maxPixel: CGFloat = 512) async -> Data? {
        await Task.detached(priority: .utility) {
            if url.pathExtension.lowercased() == "pdf",
               let document = PDFDocument(url: url), let page = document.page(at: 0) {
                let bounds = page.bounds(for: .mediaBox)
                let scale = min(maxPixel / max(bounds.width, bounds.height), 2)
                let image = page.thumbnail(of: CGSize(width: bounds.width * scale,
                                                      height: bounds.height * scale), for: .mediaBox)
                return png(from: image, maxPixel: maxPixel)
            }
            guard let image = NSImage(contentsOf: url) else { return nil }
            return png(from: image, maxPixel: maxPixel)
        }.value
    }

    public static func thumbnail(fromImageData data: Data, maxPixel: CGFloat = 512) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let image = NSImage(data: data) else { return nil }
            return png(from: image, maxPixel: maxPixel)
        }.value
    }

    /// Deliberately avoids `NSImage.lockFocus`, which fails outside a window context —
    /// thumbnails are generated on a background task with no window in sight.
    private static func png(from image: NSImage, maxPixel: CGFloat) -> Data? {
        guard var cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        if width > maxPixel || height > maxPixel {
            let scale = maxPixel / max(width, height)
            let target = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
            guard let ctx = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(origin: .zero, size: target))
            guard let scaled = ctx.makeImage() else { return nil }
            cgImage = scaled
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
