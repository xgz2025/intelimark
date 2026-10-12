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

/// A conservative token estimate for prompts sent to the on-device model, whose
/// context is 8,192 tokens (Docs/architecture.md §6.2). Characters are not tokens:
/// Chinese, Japanese and Korean use about one token per character, most other
/// scripts about one per three or four. Counting CJK characters as whole tokens
/// keeps a long Japanese page from overflowing the context.
public enum TokenBudget {
    public static func estimate(_ text: String) -> Int {
        var wide = 0
        var narrow = 0
        for scalar in text.unicodeScalars {
            if isWide(scalar) { wide += 1 } else { narrow += 1 }
        }
        return wide + (narrow + 2) / 3
    }

    /// The longest prefix of `text` that fits in `tokens`.
    public static func truncate(_ text: String, to tokens: Int) -> String {
        guard tokens > 0 else { return "" }
        guard estimate(text) > tokens else { return text }
        // Costs in thirds of a token keep the arithmetic exact.
        let limit = tokens * 3
        var cost = 0
        var end = text.startIndex
        for index in text.indices {
            let characterCost = text[index].unicodeScalars.reduce(0) { $0 + (isWide($1) ? 3 : 1) }
            if cost + characterCost > limit { break }
            cost += characterCost
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,     // Hangul Jamo
             0x2E80...0x9FFF,     // CJK radicals, kana, CJK unified ideographs
             0xA960...0xA97F,     // Hangul Jamo extended
             0xAC00...0xD7AF,     // Hangul syllables
             0xF900...0xFAFF,     // CJK compatibility ideographs
             0xFF00...0xFFEF,     // full-width forms
             0x20000...0x3FFFF:   // CJK extensions
            true
        default:
            false
        }
    }
}
