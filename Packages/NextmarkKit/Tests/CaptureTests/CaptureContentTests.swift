import Foundation
import Testing
import UniformTypeIdentifiers
import Model
@testable import Capture

struct SharedContentTests {
    @Test func linkTextBecomesTheURL() {
        var content = SharedContent(text: "  https://example.com/ramen \n")
        content.promoteLinkText()
        #expect(content.url == URL(string: "https://example.com/ramen"))
        #expect(content.text == nil)
    }

    @Test(arguments: ["Best ramen: https://example.com", "ftp://example.com/file", "https://", "just words"])
    func otherTextStaysText(text: String) {
        var content = SharedContent(text: text)
        content.promoteLinkText()
        #expect(content.url == nil)
        #expect(content.text == text)
    }

    @Test func aKnownURLIsKept() {
        var content = SharedContent(url: URL(string: "https://a.example"), text: "https://b.example")
        content.promoteLinkText()
        #expect(content.url == URL(string: "https://a.example"))
        #expect(content.text == "https://b.example")
    }

    @Test func textSelectedOnAPageBecomesAQuote() {
        var content = SharedContent(url: URL(string: "https://example.com"), text: "open until midnight")
        content.quoteTextFromPage()
        #expect(content.selection == TextQuote(exact: "open until midnight"))
        #expect(content.text == nil)

        var withoutPage = SharedContent(text: "a thought")
        withoutPage.quoteTextFromPage()
        #expect(withoutPage.selection == nil)
        #expect(withoutPage.text == "a thought")
    }
}

struct PayloadTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "PayloadTests-\(UUID().uuidString)")
    var store: EnvelopeStore { EnvelopeStore(inboxURL: root.appending(path: "Inbox")) }

    @Test func copiesFilesWithTheirType() throws {
        let source = root.appending(path: "Quarterly report.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.4".utf8).write(to: source)
        let id = ULID()

        let file = try store.addPayloadFile(copying: source, for: id, index: 2)
        #expect(file.fileName == "2-Quarterly report.pdf")
        #expect(file.contentType == UTType.pdf.identifier)
        #expect(file.byteSize == 8)
        let copied = store.directory(for: id).appending(path: "payload").appending(path: file.fileName)
        #expect(FileManager.default.fileExists(atPath: copied.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))   // a copy, not a move
    }

    @Test func writesDataPayloads() throws {
        let id = ULID()
        let file = try store.addPayload(Data([0x89, 0x50, 0x4E, 0x47]), fileName: "0-screenshot.png", contentType: .png, for: id)
        #expect(file == PayloadFile(fileName: "0-screenshot.png", contentType: "public.png", byteSize: 4))

        // A capture discarded before commit leaves nothing behind.
        try store.discard(id)
        #expect(!FileManager.default.fileExists(atPath: store.directory(for: id).path(percentEncoded: false)))
    }
}

struct FileTitleTests {
    @Test(arguments: [
        ("0-Q3 report.pdf", "Q3 report"),
        ("12-Kyoto itinerary.final.docx", "Kyoto itinerary.final"),
        ("Lease agreement.pdf", "Lease agreement"),
        ("0-2024-tax-return.pdf", "2024-tax-return"),
    ])
    func filesAreTitledByTheirName(fileName: String, title: String) {
        #expect(PayloadFile(fileName: fileName, contentType: "com.adobe.pdf").displayName == title)
    }

    @Test(arguments: ["0-IMG_1234.HEIC", "1-PXL_20261009_101500.jpg", "0-image.png", "0-.pdf", "DSC01234.JPG"])
    func meaninglessNamesAreSkipped(fileName: String) {
        #expect(PayloadFile(fileName: fileName, contentType: "public.data").displayName == nil)
    }

    @Test func aSharedFileGetsItsNameAsTitle() {
        var content = SharedContent(files: [PayloadFile(fileName: "0-Q3 report.pdf", contentType: "com.adobe.pdf")])
        content.useFileNameAsTitle()
        #expect(content.title == "Q3 report")

        // A page's own title, or a link, wins over the file name.
        var titled = SharedContent(title: "Report", files: content.files)
        titled.useFileNameAsTitle()
        #expect(titled.title == "Report")
        var linked = SharedContent(url: URL(string: "https://example.com/r.pdf"), files: content.files)
        linked.useFileNameAsTitle()
        #expect(linked.title == nil)
    }
}
