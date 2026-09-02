import AppKit
import Foundation
import Testing
@testable import SummonKit

@Suite("Heuristics")
struct HeuristicsTests {
    @Test("A title comes from the first meaningful line")
    func titleFromFirstLine() {
        #expect(Heuristics.title(forText: "Standard project terms\nPayment in 30 days")
                == "Standard project terms")
    }

    @Test("A greeting is skipped, because it says nothing about what the snippet is for")
    func skipsGreeting() {
        let text = """
        Hi {{first_name}},

        Thanks for getting in touch about the rebrand.
        """
        #expect(Heuristics.title(forText: text) == "Thanks for getting in touch about the rebrand.")
    }

    @Test("Markdown and quote markers are stripped")
    func stripsMarkers() {
        #expect(Heuristics.title(forText: "## Invoice terms") == "Invoice terms")
        #expect(Heuristics.title(forText: "> Quoted heading") == "Quoted heading")
        #expect(Heuristics.title(forText: "- A bullet") == "A bullet")
    }

    @Test("A long line is truncated at a word boundary")
    func truncatesAtWord() {
        let long = String(repeating: "word ", count: 40)
        let title = Heuristics.title(forText: long)
        #expect(title.count <= 58)
        #expect(title.hasSuffix("…"))
        #expect(!title.contains("wor…"))
    }

    @Test("Empty input still yields something usable")
    func emptyTitle() {
        #expect(Heuristics.title(forText: "   \n\n  ") == "Untitled snippet")
    }

    @Test("A filename becomes a readable title")
    func filenameTitle() {
        #expect(Heuristics.title(forFilename: "acme_proposal-v3.pdf") == "Acme proposal v3")
        #expect(Heuristics.title(forFilename: "Studio One-Pager.pdf") == "Studio One Pager")
    }

    @Test("Detectors find the things that matter in reused content")
    func tagDetection() {
        #expect(Heuristics.tags(forText: "Write to hein@example.com", kind: .text).contains("email"))
        #expect(Heuristics.tags(forText: "See https://example.com/x", kind: .text).contains("link"))
        #expect(Heuristics.tags(forText: "IBAN: NL91 ABNA 0417 1643 00", kind: .text).contains("banking"))
        #expect(Heuristics.tags(forText: "Hi {{name}}", kind: .text).contains("template"))
        #expect(Heuristics.tags(forText: "Our invoice is attached", kind: .text).contains("invoice"))
        #expect(Heuristics.tags(forText: "This NDA is binding", kind: .text).contains("legal"))
    }

    @Test("File extensions contribute a type tag")
    func extensionTags() {
        #expect(Heuristics.tags(forText: "", kind: .document, filename: "deck.key").contains("presentation"))
        #expect(Heuristics.tags(forText: "", kind: .image, filename: "logo.png").contains("image"))
    }

    @Test("Never more than four tags, so the UI stays calm")
    func tagsAreCapped() {
        let kitchenSink = "hein@example.com https://example.com IBAN NL91 ABNA 0417 1643 00 " +
                          "invoice contract proposal meeting password {{name}} +31 6 12345678"
        #expect(Heuristics.tags(forText: kitchenSink, kind: .text).count <= 4)
    }

    @Test("A summary is only offered when there is enough text to summarise")
    func summaryThreshold() {
        #expect(Heuristics.summary(forText: "Short.") == nil)
        let long = "This document explains how the studio works with new clients from first call to invoice."
        #expect(Heuristics.summary(forText: long) != nil)
    }

    @Test("Model output is tidied of quotes and trailing full stops")
    func tidyOutput() {
        #expect(Intelligence.tidy("\"Invoice reply\"") == "Invoice reply")
        #expect(Intelligence.tidy("  Client onboarding.  ") == "Client onboarding")
        // A real sentence keeps its full stop.
        #expect(Intelligence.tidy("This is a full sentence that should keep its period.")
                .hasSuffix("."))
    }
}

@Suite("Text extraction")
struct TextExtractionTests {

    /// Renders real text into a bitmap so OCR is exercised end to end rather than mocked.
    private func imageWithText(_ text: String) -> Data? {
        let size = CGSize(width: 900, height: 260)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (text as NSString).draw(at: NSPoint(x: 40, y: 100), withAttributes: [
            .font: NSFont.systemFont(ofSize: 56, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        NSGraphicsContext.current = previous

        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @Test("Vision reads the text out of an image, making its contents searchable")
    func ocrFindsText() async throws {
        let data = try #require(imageWithText("Invoice 2026-084"))
        let recognised = await TextExtractor.ocr(imageData: data)
        #expect(recognised.lowercased().contains("invoice"))
    }

    @Test("A thumbnail is produced without a window context")
    func thumbnailGeneration() async throws {
        let data = try #require(imageWithText("Preview"))
        let thumbnail = await TextExtractor.thumbnail(fromImageData: data, maxPixel: 128)
        let png = try #require(thumbnail)
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide <= 128)
        #expect(rep.pixelsHigh <= 128)
    }

    @Test("PDF text is extracted from the text layer")
    func pdfTextExtraction() async throws {
        let pdf = try #require(await MainActor.run { StarterLibrary.makeOnePagerPDF() })
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "summon-test-\(UUID().uuidString).pdf")
        try pdf.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = await TextExtractor.documentText(url: url)
        #expect(text.contains("Summon Studio"))
        #expect(text.contains("discovery call"))
    }

    @Test("Generated starter assets are valid images and documents")
    @MainActor
    func starterAssetsAreValid() throws {
        let logo = try #require(StarterLibrary.makeLogoPNG())
        let rep = try #require(NSBitmapImageRep(data: logo))
        #expect(rep.pixelsWide == 512)

        let pdf = try #require(StarterLibrary.makeOnePagerPDF())
        #expect(pdf.count > 1000)
    }
}
