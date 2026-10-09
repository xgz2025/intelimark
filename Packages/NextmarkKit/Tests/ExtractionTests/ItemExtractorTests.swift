import Foundation
import Testing
import Model
@testable import Extraction

struct ItemExtractorTests {
    @Test func fetchesAndParsesALink() async throws {
        let fetcher = FakeFetcher.html(Fixtures.productPage)
        let extractor = ItemExtractor(fetcher: fetcher, imageAnalyzer: nil)

        let extraction = try await extractor.extract(ExtractionInput(kind: .link, url: Fixtures.pageURL))

        #expect(fetcher.requests == [Fixtures.pageURL])
        #expect(extraction.title == "Aeron Chair")
        #expect(extraction.siteName == "Herman Miller")
        #expect(extraction.contentText?.contains("Twelve-year warranty.") == true)
        #expect(extraction.structured?.kind == .product)
        #expect(extraction.structured?.fields.product?.price == 1395)
    }

    @Test func usesSafarisCaptureWithoutFetching() async throws {
        let fetcher = FakeFetcher.html("<p>should not be fetched</p>")
        let page = PageContext(language: "ja", excerpt: "Members-only article text", jsonLD: [#"{"@type":"Recipe","name":"Oden"}"#])
        let extraction = try await ItemExtractor(fetcher: fetcher, imageAnalyzer: nil)
            .extract(ExtractionInput(kind: .link, url: Fixtures.pageURL, pageContext: page))

        #expect(fetcher.requests.isEmpty)
        #expect(extraction.contentText == "Members-only article text")
        #expect(extraction.language == "ja")
        #expect(extraction.structured?.kind == .recipe)
    }

    @Test func offlineIsRetryable() async {
        let fetcher = FakeFetcher { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: ExtractionError.self) {
            try await ItemExtractor(fetcher: fetcher, imageAnalyzer: nil).extract(ExtractionInput(kind: .link, url: Fixtures.pageURL))
        }
    }

    @Test func serverErrorsAreRetryableButMissingPagesAreNot() async throws {
        await #expect(throws: ExtractionError.self) {
            try await ItemExtractor(fetcher: FakeFetcher.html("busy", status: 503), imageAnalyzer: nil)
                .extract(ExtractionInput(kind: .link, url: Fixtures.pageURL))
        }
        let missing = try await ItemExtractor(fetcher: FakeFetcher.html("gone", status: 404), imageAnalyzer: nil)
            .extract(ExtractionInput(kind: .link, url: Fixtures.pageURL))
        #expect(missing == Extraction())
    }

    @Test func textAndNotesNeedNoExtraction() async throws {
        let fetcher = FakeFetcher.html("")
        let extraction = try await ItemExtractor(fetcher: fetcher, imageAnalyzer: nil).extract(ExtractionInput(kind: .text))
        #expect(extraction == Extraction())
        #expect(fetcher.requests.isEmpty)
    }

    @Test func readsPlainTextFiles() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let file = directory.appending(path: "notes.txt")
        try Data("  Packing list: passport, adapter  \n".utf8).write(to: file)
        let extraction = try await ItemExtractor(fetcher: FakeFetcher.html(""), imageAnalyzer: nil)
            .extract(ExtractionInput(kind: .file, files: [LocalFile(url: file, contentType: "public.plain-text")]))
        #expect(extraction.contentText == "Packing list: passport, adapter")
    }

    #if canImport(PDFKit)
    @Test func extractsPDFText() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let file = directory.appending(path: "itinerary.pdf")
        try Fixtures.makePDF(text: "Nextmark itinerary Kyoto", at: file)
        let extraction = try await ItemExtractor(fetcher: FakeFetcher.html(""), imageAnalyzer: nil)
            .extract(ExtractionInput(kind: .pdf, files: [LocalFile(url: file, contentType: "com.adobe.pdf")]))
        #expect(extraction.contentText?.contains("Nextmark itinerary Kyoto") == true)
    }
    #endif

    #if canImport(Vision)
    @Test func recognizesTextInImages() async throws {
        let directory = try Fixtures.temporaryDirectory()
        let file = directory.appending(path: "screenshot.png")
        try Fixtures.makePNG(text: "NEXTMARK 2026", at: file)
        let extraction = try await ItemExtractor(fetcher: FakeFetcher.html(""))
            .extract(ExtractionInput(kind: .image, files: [LocalFile(url: file, contentType: "public.png")]))
        let text = try #require(extraction.ocrText)
        #expect(text.uppercased().contains("NEXTMARK"))
    }
    #endif
}
