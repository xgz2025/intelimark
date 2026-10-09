import Foundation
import Testing
@testable import Extraction

struct HTMLParserTests {
    @Test func readsOpenGraphCanonicalAndJSONLD() {
        let metadata = HTMLParser.metadata(from: Fixtures.productPage, baseURL: Fixtures.pageURL)
        #expect(metadata.title == "Aeron Chair")
        #expect(metadata.siteName == "Herman Miller")
        #expect(metadata.description == "The benchmark for ergonomic seating.")
        #expect(metadata.language == "en")
        #expect(metadata.canonicalURL == URL(string: "https://store.example.com/aeron"))
        #expect(metadata.imageURL == URL(string: "https://store.example.com/images/aeron.jpg"))
        #expect(metadata.jsonLD.count == 1)   // the analytics script is not JSON-LD
    }

    @Test func fallsBackToTheDocumentTitle() {
        let html = "<html><head><title>\n  Caf&eacute; &amp; Bar &#8212; Kyoto </title></head></html>"
        #expect(HTMLParser.metadata(from: html, baseURL: nil).title == "Café & Bar — Kyoto")
    }

    @Test func handlesSingleQuotedAndUnquotedAttributes() {
        let html = "<meta property='og:site_name' content='Quoted'><meta name=description content=Bare>"
        let metadata = HTMLParser.metadata(from: html, baseURL: nil)
        #expect(metadata.siteName == "Quoted")
        #expect(metadata.description == "Bare")
    }

    @Test func rejectsNonHTTPImageURLs() {
        let html = #"<meta property="og:image" content="javascript:alert(1)">"#
        #expect(HTMLParser.metadata(from: html, baseURL: Fixtures.pageURL).imageURL == nil)
    }

    @Test func decodesEntities() {
        #expect(HTMLText.decodeEntities("&lt;b&gt; &#39;x&#39; &#x263A; caf&eacute; &bogus;") == "<b> 'x' ☺ café &bogus;")
    }
}

struct ReadableTextTests {
    @Test func prefersTheArticleAndDropsChrome() throws {
        let text = try #require(ReadableText.extract(fromHTML: Fixtures.productPage))
        #expect(text == "Aeron Chair\nDesigned for & by people who sit all day.\nTwelve-year warranty.")
    }

    @Test func fallsBackToTheBodyAndKeepsListItems() {
        let html = "<html><body><p>One</p><ul><li>Two</li><li>Three</li></ul></body></html>"
        #expect(ReadableText.extract(fromHTML: html) == "One\n• Two\n• Three")
    }

    @Test func truncatesAtAWordBoundary() throws {
        let html = "<p>" + String(repeating: "word ", count: 100) + "</p>"
        let text = try #require(ReadableText.extract(fromHTML: html, maxCharacters: 22))
        #expect(text == "word word word word")
    }

    @Test func emptyPagesHaveNoText() {
        #expect(ReadableText.extract(fromHTML: "<html><body><script>x()</script></body></html>") == nil)
    }
}
