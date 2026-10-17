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

/// The words a page has for getting around it, not about what it is: skip links,
/// sign-in prompts, menus ("Skip to main content", "Hi! Sign in or register"). Left out
/// of summaries and snippets, which would otherwise start with them.
public enum PageText {
    /// Lines that are only page furniture, compared lowercased without punctuation.
    static let furniture: Set<String> = [
        "skip to", "skip to main content", "skip to content", "skip to footer", "skip to navigation",
        "skip to main navigation", "skip to search", "skip to product information", "main content", "content",
        "hi sign in or register", "sign in or register", "sign in", "sign up", "register", "log in", "login",
        "menu", "cart", "account", "my account", "search", "close", "back to top", "home", "help",
        "accessibility", "accessibility help", "keyboard shortcuts", "shop by category", "all categories",
        "跳到主要内容", "登录", "注册", "购物车", "搜索", "首页", "菜单",
    ]

    /// `text` without lines of page furniture, and without the skip links run together at
    /// its start ("skip to main contentskip to footer").
    public static func withoutFurniture(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var line = line.trimmingCharacters(in: .whitespaces)
            while let skip = line.firstMatch(of: #/(?i)^(?:skip to (?:main |the )?(?:content|footer|navigation|search))\s*/#) {
                line.removeSubrange(skip.range)
            }
            return line.isEmpty || isFurniture(line) ? nil : line
        }
        return lines.joined(separator: "\n")
    }

    public static func isFurniture(_ line: String) -> Bool {
        let key = line.lowercased()
            .unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
            .map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
        return key.count <= 1 || furniture.contains(key)
    }
}
