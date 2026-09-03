import Darwin
import Foundation
import Testing
@testable import SummonKit

/// A one-shot loopback listener, used to assert that extraction makes no request.
///
/// The point of the test below is a claim the README makes in plain words — "no
/// networking code — the app makes no outbound requests at all" — so the assertion
/// has to be that a socket never gets connected to, not that some flag is set.
private final class LoopbackProbe {
    let port: UInt16
    private let socketFD: Int32
    private let connected = Atomic()

    /// A tiny box so the accept loop and the test can share one flag safely.
    final class Atomic: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var wasHit: Bool { lock.withLock { value } }
        func hit() { lock.withLock { value = true } }
    }

    init?() {
        // Held locally until every member is set: the pointer closures below would
        // otherwise be capturing a half-initialised `self`.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0  // Let the kernel choose, so parallel tests cannot collide.
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 4) == 0 else {
            close(fd)
            return nil
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            close(fd)
            return nil
        }

        socketFD = fd
        port = actual.sin_port.byteSwapped

        let flag = connected
        Thread.detachNewThread {
            // Blocks until something connects or the socket is closed underneath it.
            let client = accept(fd, nil, nil)
            if client >= 0 {
                flag.hit()
                close(client)
            }
        }
    }

    var wasContacted: Bool { connected.wasHit }

    func shutDown() { close(socketFD) }
}

@Suite("Document text extraction")
struct DocumentReadingTests {

    private func write(_ contents: String, extension ext: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "extract-\(UUID().uuidString).\(ext)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("Importing an HTML file makes no outbound request")
    func htmlNeverReachesTheNetwork() async throws {
        let probe = try #require(LoopbackProbe(), "could not open a loopback listener")
        defer { probe.shutDown() }

        // AppKit's HTML reader is WebKit-backed and fetches this. Ours must not.
        let url = try write("""
        <html><body><h1>Quarterly report</h1>
        <img src="http://127.0.0.1:\(probe.port)/beacon">
        </body></html>
        """, extension: "html")
        defer { try? FileManager.default.removeItem(at: url) }

        let text = await TextExtractor.documentText(url: url)

        // The content still has to be searchable — a fix that extracted nothing would
        // pass the network assertion and break the feature.
        #expect(text.contains("Quarterly report"))
        #expect(!text.contains("127.0.0.1"))

        // Give a request that was going to happen time to arrive.
        try? await Task.sleep(for: .milliseconds(750))
        #expect(!probe.wasContacted, "extraction opened a connection to \(probe.port)")
    }

    @Test("A web archive is not handed to the framework reader either")
    func webArchiveNeverReachesTheNetwork() async throws {
        let probe = try #require(LoopbackProbe(), "could not open a loopback listener")
        defer { probe.shutDown() }

        // A .webarchive is a plist wrapping the markup; the reader would follow it.
        let url = try write("""
        <html><body>Archived note
        <img src="http://127.0.0.1:\(probe.port)/beacon"></body></html>
        """, extension: "webarchive")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = await TextExtractor.documentText(url: url)
        try? await Task.sleep(for: .milliseconds(750))
        #expect(!probe.wasContacted)
    }

    @Test("Markup is reduced to its words")
    func stripsMarkupToText() {
        let html = """
        <html><head><title>Ignored</title><style>body{color:red}</style></head>
        <body><script>var secret = "script body";</script>
        <h1>Invoice&nbsp;terms</h1>
        <!-- a comment -->
        <p>Payment in 30 days &amp; 12&#37; late fee.</p></body></html>
        """
        let text = TextExtractor.strippedMarkup(from: Data(html.utf8))

        // `&nbsp;` decodes and then collapses to a normal space, which is what the
        // search index wants: typing "invoice terms" should still match.
        #expect(text.contains("Invoice terms"))
        #expect(text.contains("Payment in 30 days & 12% late fee."))
        // Script, style, head and comment contents carry no words worth indexing.
        #expect(!text.contains("script body"))
        #expect(!text.contains("color:red"))
        #expect(!text.contains("Ignored"))
        #expect(!text.contains("a comment"))
        // No angle brackets survive, so nothing downstream sees markup.
        #expect(!text.contains("<"))
    }

    @Test("A plain text file reads as itself")
    func plainTextReadsDirectly() async throws {
        let url = try write("VAT NL0012 3456 B01", extension: "txt")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextExtractor.documentText(url: url) == "VAT NL0012 3456 B01")
    }

    @Test("An unreadable binary yields nothing rather than garbage")
    func unsupportedYieldsEmpty() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "extract-\(UUID().uuidString).xlsx")
        try Data([0x50, 0x4B, 0x03, 0x04, 0xFF, 0xFE]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await TextExtractor.documentText(url: url).isEmpty)
    }
}
