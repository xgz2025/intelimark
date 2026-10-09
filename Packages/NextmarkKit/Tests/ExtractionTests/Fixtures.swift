import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Extraction

enum Fixtures {
    static let productPage = """
        <!doctype html>
        <html lang="en"><head>
        <meta charset="utf-8">
        <title>Aeron Chair | Herman Miller Store</title>
        <meta property="og:title" content="Aeron Chair">
        <meta property="og:site_name" content="Herman Miller">
        <meta name="description" content="The benchmark for ergonomic seating.">
        <meta property="og:image" content="/images/aeron.jpg">
        <link rel="canonical" href="https://store.example.com/aeron">
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Aeron"},
          {"@type":"Product","name":"Aeron Chair","brand":{"@type":"Brand","name":"Herman Miller"},
           "offers":{"@type":"Offer","price":"1395.00","priceCurrency":"USD","availability":"https://schema.org/InStock"}}
        ]}
        </script>
        <script>window.analytics = {};</script>
        <style>body { margin: 0 }</style>
        </head>
        <body>
        <nav>Home Shop Cart</nav>
        <header>Big header</header>
        <!-- promo banner -->
        <article><h1>Aeron Chair</h1><p>Designed for &amp; by people who sit all day.</p><p>Twelve-year warranty.</p><script>track()</script></article>
        <footer>© 2026 Herman Miller</footer>
        </body></html>
        """

    static let pageURL = URL(string: "https://store.example.com/p/aeron?ref=home")!

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ExtractionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        return NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    }

    /// A one-page PDF with real (extractable) text.
    static func makePDF(text: String, at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(attributed(text, size: 24) as CFAttributedString), context)
        context.endPDFPage()
        context.closePDF()
    }

    /// Black text on white, large enough for OCR.
    static func makePNG(text: String, at url: URL) throws {
        let width = 1400, height = 320
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.textPosition = CGPoint(x: 60, y: 120)
        CTLineDraw(CTLineCreateWithAttributedString(attributed(text, size: 110) as CFAttributedString), context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

/// A fetcher that serves canned responses and counts requests.
final class FakeFetcher: PageFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URL] = []
    private let respond: @Sendable (URL) throws -> FetchedResource

    init(respond: @escaping @Sendable (URL) throws -> FetchedResource) {
        self.respond = respond
    }

    static func html(_ html: String, status: Int = 200) -> FakeFetcher {
        FakeFetcher { url in
            FetchedResource(data: Data(html.utf8), mimeType: "text/html", textEncodingName: "utf-8", finalURL: url, statusCode: status)
        }
    }

    var requests: [URL] {
        lock.withLock { _requests }
    }

    func fetch(_ url: URL) async throws -> FetchedResource {
        lock.withLock { _requests.append(url) }
        return try respond(url)
    }
}
