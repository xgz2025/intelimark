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
@testable import Capture

struct TextFragmentTests {
    let page = URL(string: "https://example.com/article")!

    @Test func shortQuoteIsEncodedInFull() {
        let url = TextFragment.url(for: page, quote: TextQuote(exact: "hello  world"))
        #expect(url?.absoluteString == "https://example.com/article#:~:text=hello%20world")
    }

    @Test func contextBecomesPrefixAndSuffix() {
        let quote = TextQuote(exact: "the quick fox", prefix: "and then", suffix: "jumped over it all")
        let url = TextFragment.url(for: page, quote: quote)
        #expect(url?.absoluteString == "https://example.com/article#:~:text=and%20then-,the%20quick%20fox,-jumped%20over%20it")
    }

    @Test func longQuoteUsesStartAndEnd() {
        let quote = TextQuote(exact: "one two three four five six seven eight nine ten")
        let url = TextFragment.url(for: page, quote: quote)
        #expect(url?.absoluteString == "https://example.com/article#:~:text=one%20two%20three%20four,seven%20eight%20nine%20ten")
    }

    @Test func directiveSyntaxCharactersAreEscaped() {
        let url = TextFragment.url(for: page, quote: TextQuote(exact: "a-b, c&d"))
        #expect(url?.absoluteString == "https://example.com/article#:~:text=a%2Db%2C%20c%26d")
    }

    @Test func keepsExistingFragmentAndReplacesExistingDirective() {
        let withFragment = URL(string: "https://example.com/a#section:~:text=old")!
        let url = TextFragment.url(for: withFragment, quote: TextQuote(exact: "new"))
        #expect(url?.absoluteString == "https://example.com/a#section:~:text=new")
    }

    @Test func emptyQuoteHasNoFragment() {
        #expect(TextFragment.url(for: page, quote: TextQuote(exact: "   ")) == nil)
    }
}
