import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
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

    /// How one document's text gets read.
    ///
    /// Chosen from the file's uniform type rather than left to AppKit, which is the
    /// whole point of this enum — see `documentText(url:)`.
    private enum Reader {
        case pdf
        /// An `NSAttributedString` reader, named explicitly so none can be inferred.
        case attributed(NSAttributedString.DocumentType)
        /// Markup we strip ourselves instead of handing to WebKit.
        case markup
        case plain
        case unsupported
    }

    private static func reader(for url: URL) -> Reader {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .plain }

        if type.conforms(to: .pdf) { return .pdf }

        // HTML and web archives are read by us, not by AppKit. Its HTML reader is
        // WebKit-backed and resolves remote subresources, so an `<img src="https://…">`
        // in an imported file was an outbound request from an app that documents itself
        // as making none — and enrichment runs on *decrypted* content, so a sealed
        // document could be made to call out. See `strippedMarkup(from:)`.
        if type.conforms(to: .html) || type.conforms(to: .xml)
            || type.conforms(to: .webArchive) { return .markup }

        if type.conforms(to: .rtf) { return .attributed(.rtf) }
        // No UTType statics exist for these three, so they are resolved by identifier.
        for (wordProcessor, documentType) in Self.wordProcessorTypes
        where type.conforms(to: wordProcessor) {
            return .attributed(documentType)
        }

        if type.conforms(to: .text) { return .plain }
        return .unsupported
    }

    private static let wordProcessorTypes: [(UTType, NSAttributedString.DocumentType)] =
        [
            ("com.microsoft.word.doc", .docFormat),
            ("org.openxmlformats.wordprocessingml.document", .officeOpenXML),
            ("org.oasis-open.opendocument.text", .openDocument),
        ].compactMap { identifier, documentType in
            UTType(identifier).map { ($0, documentType) }
        }

    public static func documentText(url: URL) async -> String {
        await Task.detached(priority: .utility) {
            switch reader(for: url) {
            case .pdf:
                return pdfText(url: url)

            case .attributed(let documentType):
                // Read from `Data`, not from the URL: the URL form sets a base URL the
                // readers use to resolve relative references, and passing the type
                // explicitly is what stops one being sniffed from the contents.
                guard let data = try? Data(contentsOf: url),
                      let attributed = try? NSAttributedString(
                          data: data,
                          options: [.documentType: documentType],
                          documentAttributes: nil
                      )
                else { return plainText(url: url) }
                return String(attributed.string.prefix(maxCharacters))

            case .markup:
                guard let data = try? Data(contentsOf: url) else { return "" }
                return strippedMarkup(from: data)

            case .plain:
                return plainText(url: url)

            case .unsupported:
                return ""
            }
        }.value
    }

    private static func plainText(url: URL) -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return String(text.prefix(maxCharacters))
        }
        // Falls back for the legacy encodings a plain .txt still shows up in.
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1) {
            return String(text.prefix(maxCharacters))
        }
        return ""
    }

    // MARK: - Markup

    /// Words out of markup, with nothing resolved and nothing fetched.
    ///
    /// Extraction only needs text for the search index, so tags go and their contents
    /// stay. Deliberately hand-rolled: every framework reader for these formats is
    /// WebKit-backed, and none of them can be told not to touch the network with any
    /// confidence worth relying on.
    static func strippedMarkup(from data: Data) -> String {
        guard var source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { return "" }

        // Bounded before any pattern runs, so a pathological file cannot make the
        // scan expensive. Four bytes per output character is generous for markup.
        source = String(source.prefix(maxCharacters * 4))

        for element in ["script", "style", "head"] {
            source = source.replacingOccurrences(
                of: "<\(element)\\b[^>]*>[\\s\\S]*?</\(element)\\s*>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Comments, CDATA and processing instructions, then every remaining tag.
        source = source.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ",
                                             options: .regularExpression)
        source = source.replacingOccurrences(of: "<[^>]*>", with: " ",
                                             options: .regularExpression)

        return String(collapsingWhitespace(decodingEntities(source)).prefix(maxCharacters))
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "eacute": "é",
    ]

    private static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var rest = Substring(text)

        while let start = rest.firstIndex(of: "&") {
            out += rest[rest.startIndex..<start]
            let after = rest.index(after: start)
            // An entity is short; anything longer is a stray ampersand.
            let window = rest[after...].prefix(12)
            guard let semi = window.firstIndex(of: ";") else {
                out.append("&")
                rest = rest[after...]
                continue
            }
            let name = rest[after..<semi]
            if name.hasPrefix("#"),
               let scalar = numericEntity(name.dropFirst()) {
                out.append(Character(scalar))
            } else if let replacement = namedEntities[name.lowercased()] {
                out += replacement
            } else {
                out += "&\(name);"
            }
            rest = rest[rest.index(after: semi)...]
        }
        out += rest
        return out
    }

    private static func numericEntity(_ digits: Substring) -> Unicode.Scalar? {
        let value = digits.first.map({ $0 == "x" || $0 == "X" })  == true
            ? UInt32(digits.dropFirst(), radix: 16)
            : UInt32(digits, radix: 10)
        return value.flatMap(Unicode.Scalar.init)
    }

    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
