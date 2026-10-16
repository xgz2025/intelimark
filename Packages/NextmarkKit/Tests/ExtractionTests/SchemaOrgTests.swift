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
@testable import Extraction

struct SchemaOrgTests {
    @Test func productInAGraph() throws {
        let blocks = HTMLParser.metadata(from: Fixtures.productPage, baseURL: nil).jsonLD
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: blocks))
        #expect(structured.kind == .product)
        #expect(structured.fields.product == ProductFields(
            name: "Aeron Chair", brand: "Herman Miller", price: 1395, currency: "USD", availability: "InStock", origin: .page
        ))
    }

    @Test func recipeWithDurationAndYield() throws {
        let json = """
            {"@context":"https://schema.org","@type":"Recipe","name":"Miso ramen",
             "recipeIngredient":["200 g  noodles","2 tbsp miso"],"totalTime":"PT1H15M","recipeYield":["4","4 servings"]}
            """
        let recipe = try #require(SchemaOrg.structuredData(fromJSONLD: [json])?.fields.recipe)
        #expect(recipe == RecipeFields(name: "Miso ramen", ingredients: ["200 g noodles", "2 tbsp miso"], totalMinutes: 75, servings: "4"))
    }

    @Test func eventSubtypeWithLocation() throws {
        let json = """
            [{"@type":"MusicEvent","name":"Autumn concert","startDate":"2026-11-20T19:30:00+09:00",
              "location":{"@type":"Place","name":"Budokan",
                "address":{"@type":"PostalAddress","streetAddress":"2-3 Kitanomaru","addressLocality":"Tokyo","addressCountry":"JP"}}}]
            """
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: [json]))
        #expect(structured.kind == .event)
        let event = try #require(structured.fields.event)
        #expect(event.startDate == ISO8601DateFormatter().date(from: "2026-11-20T10:30:00Z"))
        #expect(event.venue == "Budokan")
        #expect(event.address == "2-3 Kitanomaru, Tokyo, JP")
    }

    @Test func restaurantWithStringCoordinates() throws {
        let json = """
            {"@type":["Restaurant","LocalBusiness"],"name":"Ramen Ichi","telephone":"+81 75 000 0000",
             "geo":{"@type":"GeoCoordinates","latitude":"35.0116","longitude":135.7681}}
            """
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: [json]))
        #expect(structured.kind == .place)
        #expect(structured.fields.place?.latitude == 35.0116)
        #expect(structured.fields.place?.longitude == 135.7681)
    }

    @Test func articleWinsOverItsAuthor() throws {
        let person = #"{"@type":"Person","name":"Ann"}"#
        let article = """
            {"@type":"NewsArticle","headline":"Kyoto in autumn","author":[{"@type":"Person","name":"Ann"}],
             "publisher":{"@type":"Organization","name":"Times"},"datePublished":"2026-10-01"}
            """
        let structured = try #require(SchemaOrg.structuredData(fromJSONLD: [person, article]))
        #expect(structured.kind == .article)
        #expect(structured.fields.article?.author == "Ann")
        #expect(structured.fields.article?.publisher == "Times")
        #expect(structured.fields.article?.publishedAt == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
    }

    @Test func productBeatsArticleOnTheSamePage() {
        let blocks = [#"{"@type":"Article","headline":"Review"}"#, #"{"@type":"Product","name":"Desk"}"#]
        #expect(SchemaOrg.structuredData(fromJSONLD: blocks)?.kind == .product)
    }

    @Test func ignoresInvalidAndUninterestingData() {
        #expect(SchemaOrg.structuredData(fromJSONLD: ["{not json"]) == nil)
        #expect(SchemaOrg.structuredData(fromJSONLD: [#"{"@type":"WebSite","name":"x"}"#]) == nil)
    }

    @Test(arguments: [
        ("PT45M", 45 as Int?), ("P1DT2H", 1560), ("pt1h", 60), ("PT0S", nil), ("90 minutes", nil),
        // Absurd values from a page are ignored rather than overflowing.
        ("P9999999999999999999999D", nil), ("PT200000000000000000H", nil),
    ])
    func durations(text: String, minutes: Int?) {
        #expect(SchemaDuration.minutes(text) == minutes)
    }

    @Test func aDateWithoutATimeIsThatDayWhereTheUserIs() throws {
        let date = try #require(SchemaDate.parse("2026-11-21"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 21 && parts.hour == 0)
    }
}
