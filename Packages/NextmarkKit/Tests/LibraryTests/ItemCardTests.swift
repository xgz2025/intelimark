//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Foundation
import Testing
import Model
import Capture
@testable import Library

struct ItemCardTests {
    func item(_ kind: ItemKind, url: String? = nil, title: String? = nil) -> ItemRecord {
        var item = ItemRecord(
            envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: url.flatMap { URL(string: $0) }, title: title)
        )
        item.kind = kind
        return item
    }

    @Test func aReceiptShowsItsMerchantAndTotal() {
        var receipt = item(.image)
        receipt.aiTitle = "Coffee receipt"
        receipt.semanticKind = .receipt
        receipt.typedFields = TypedFields(receipt: ReceiptFields(merchant: "Blue Bottle Coffee", total: 10.61, currency: "USD"))
        let card = receipt.card
        #expect(card.style == .receipt)
        #expect(card.title == "Blue Bottle Coffee")
        #expect(card.figure == 10.61.formatted(.currency(code: "USD")))
        #expect(card.snippet == nil)
    }

    @Test func aPageReadsLikeASearchResult() {
        var page = item(.link, url: "https://www.example.com/recipes/ramen-guide?ref=1", title: "The Ramen Guide")
        page.summary = "Everything about broth, noodles and toppings."
        let card = page.card
        #expect(card.style == .web)
        #expect(card.source == "example.com › recipes › ramen-guide")
        #expect(card.title == "The Ramen Guide")
        #expect(card.snippet == "Everything about broth, noodles and toppings.")
    }

    @Test func aDocumentShowsItsTitleAndAuthor() {
        var document = item(.pdf, title: "draft-final-2.pdf")
        document.summary = "A proposal for the new library."
        document.typedFields = TypedFields(article: ArticleFields(headline: "Library Proposal", author: "Jane Doe"))
        let card = document.card
        #expect(card.style == .document)
        #expect(card.title == "Library Proposal")
        #expect(card.byline == "Jane Doe")
        #expect(card.snippet == "A proposal for the new library.")
    }

    @Test func aPhotoShowsWhereItWasTaken() {
        var photo = item(.image)
        photo.aiTitle = "Sunset over the bay"
        photo.imageDescription = "The sun setting behind the Golden Gate Bridge."
        let taken = Date(timeIntervalSince1970: 1_791_020_527)
        photo.typedFields = TypedFields(photo: PhotoFields(takenAt: taken, latitude: 37.8, longitude: -122.4, placeName: "San Francisco"))
        let card = photo.card
        #expect(card.style == .photo)
        #expect(card.byline == "San Francisco · " + taken.formatted(date: .abbreviated, time: .omitted))
        #expect(card.snippet == "The sun setting behind the Golden Gate Bridge.")
    }

    @Test func theUsersTitleAlwaysWins() {
        var document = item(.pdf, title: "file.pdf")
        document.userTitle = "My contract"
        document.typedFields = TypedFields(article: ArticleFields(headline: "Agreement"))
        #expect(document.card.title == "My contract")
    }
}
