import AppKit
import Foundation
import SummonKit

/// A small, realistic starting library so the first summon shows what good looks like
/// instead of an empty box. Generates real files, so image previews, PDF rendering
/// and text extraction all work from the first run.
@MainActor
public enum StarterLibrary {

    public static func seed(into store: LibraryStore, importer: Importer) async {
        guard store.snapshots.isEmpty else { return }

        let replies = store.createFolder(name: "Client Replies", symbolName: "envelope", colorName: "violet")
        let documents = store.createFolder(name: "Documents", symbolName: "doc.richtext", colorName: "amber")
        let contracts = store.createFolder(name: "Contracts", parent: documents,
                                           symbolName: "signature", colorName: "amber")
        let details = store.createFolder(name: "Form Details", symbolName: "list.bullet.rectangle",
                                         colorName: "teal")
        let assets = store.createFolder(name: "Brand Assets", symbolName: "paintpalette", colorName: "blue")

        // MARK: Snippets

        store.createSnippet(
            title: "New enquiry — first reply",
            body: """
            Hi {{first_name}},

            Thanks for getting in touch about {{project:your project}}. I'd be glad to help.

            I've attached an overview of how I usually work, along with indicative timings. \
            If it looks like a fit, I have availability from {{date:+7d}} and can put together \
            a proper proposal.

            {{cursor}}

            Best,
            Hein
            """,
            folder: replies, tags: ["email", "sales"], pinned: true
        )

        store.createSnippet(
            title: "Meeting follow-up",
            body: """
            Hi {{first_name}},

            Good to speak just now. To summarise what we agreed:

            • {{point_one}}
            • {{point_two}}

            I'll come back to you by {{date:+3d}}. Shout if I've missed anything.

            Best,
            Hein
            """,
            folder: replies, tags: ["email", "meetings"]
        )

        store.createSnippet(
            title: "Politely declining new work",
            body: """
            Hi {{first_name}},

            Thank you for thinking of me for this — it sounds like a genuinely interesting piece of work.

            Unfortunately my calendar is full through {{date:+30d}}, so I'd rather say no now than \
            hold you up. If timings shift on your side, do come back to me.

            Best of luck with it,
            Hein
            """,
            folder: replies, tags: ["email"]
        )

        store.createSnippet(
            title: "Invoice payment details",
            body: """
            Account name: Hein de Wilde
            IBAN: NL91 ABNA 0417 1643 00
            BIC: ABNANL2A
            VAT: NL001234567B01
            Reference: {{invoice_number}}
            """,
            folder: details, tags: ["banking", "invoice"], pinned: true
        )

        // A formatted snippet, so the rich-text path is real from the first run.
        let signature = NSMutableAttributedString()
        signature.append(NSAttributedString(string: "Hein de Wilde\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]))
        signature.append(NSAttributedString(string: "Summon Studio · Amsterdam\nhein@summon.studio", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        store.createSnippet(
            title: "Email signature",
            body: signature.string,
            rtf: RTF.data(from: signature),
            folder: details, tags: ["email"]
        )

        store.createSnippet(
            title: "Company address",
            body: """
            Summon Studio
            Keizersgracht 241
            1016 EA Amsterdam
            The Netherlands
            """,
            folder: details, tags: ["contact"]
        )

        store.createSnippet(
            title: "Short bio",
            body: """
            Hein de Wilde builds tools that make everyday work quieter. He has spent fifteen years \
            designing software for people who care about craft, and writes about the overlap \
            between speed and taste.
            """,
            folder: details, tags: ["template"]
        )

        store.createSnippet(
            title: "Standard project terms",
            body: """
            Payment terms: 30 days from invoice date.
            Revisions: two rounds included per deliverable.
            Cancellation: 50% of the remaining fee if cancelled after kick-off.
            Ownership: all delivered work transfers on final payment.
            """,
            folder: contracts, tags: ["legal"]
        )

        // MARK: Generated files

        let scratch = FileStore.scratchDirectory()

        if let logo = makeLogoPNG() {
            let url = scratch.appending(path: "Summon Logo.png")
            try? logo.write(to: url)
            _ = await importer.importFiles([url], into: assets).first
        }

        if let pdf = makeOnePagerPDF() {
            let url = scratch.appending(path: "Studio One-Pager.pdf")
            try? pdf.write(to: url)
            _ = await importer.importFiles([url], into: documents).first
        }

        store.refresh()
    }

    // MARK: - Generated assets

    static func makeLogoPNG() -> Data? {
        let side = 512
        guard let ctx = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 110, cornerHeight: 110, transform: nil))
        ctx.setFillColor(CGColor(red: 0.36, green: 0.25, blue: 0.78, alpha: 1))
        ctx.fillPath()

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let text = "S" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 300, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (CGFloat(side) - bounds.width) / 2,
                              y: (CGFloat(side) - bounds.height) / 2),
                  withAttributes: attributes)
        NSGraphicsContext.current = previous

        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func makeOnePagerPDF() -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72dpi
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(pageRect)
        ctx.setFillColor(CGColor(red: 0.36, green: 0.25, blue: 0.78, alpha: 1))
        ctx.fill(CGRect(x: 0, y: pageRect.height - 8, width: pageRect.width, height: 8))

        draw("Summon Studio", at: CGPoint(x: 56, y: 720), size: 30, weight: .bold)
        draw("How I work", at: CGPoint(x: 56, y: 672), size: 16, weight: .semibold,
             color: NSColor(srgbRed: 0.36, green: 0.25, blue: 0.78, alpha: 1))

        let body = """
        Every engagement starts with a short discovery call, at no cost, so we can both \
        decide whether the work is a fit.

        From there I write a one-page brief covering scope, timings and price. Nothing \
        starts until you have signed that off, and the price does not move afterwards \
        unless the scope does.

        Delivery happens in weekly increments. You will see working software every Friday, \
        not a status report. Two rounds of revisions are included per deliverable.

        Invoices go out on the first of the month, payable within thirty days. All work \
        transfers to you on final payment.
        """
        drawParagraph(body, in: CGRect(x: 56, y: 380, width: pageRect.width - 112, height: 260))

        draw("hein@summon.studio  ·  Keizersgracht 241, Amsterdam",
             at: CGPoint(x: 56, y: 64), size: 10, weight: .regular,
             color: NSColor(srgbRed: 0.42, green: 0.42, blue: 0.48, alpha: 1))

        NSGraphicsContext.current = previous
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat,
                             weight: NSFont.Weight, color: NSColor = .black) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ])
    }

    private static func drawParagraph(_ text: String, in rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.2, alpha: 1),
            .paragraphStyle: style,
        ])
    }
}
