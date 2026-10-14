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
import Model

/// Reads the merchant and total from a receipt's recognized text, without a model,
/// so it works on every device. Says nothing unless the text clearly is a receipt:
/// a total line with an amount, and other signs of one.
public enum ReceiptParser {
    static let totalWords = [
        "grand total", "total due", "amount due", "balance due", "total amount", "total",
        "amount", "合计", "总计", "合計", "総計", "お会計", "summe", "gesamt", "montant", "importe",
    ]
    static let receiptWords = [
        "subtotal", "sub total", "tax", "vat", "gst", "tip", "change", "cash", "card", "visa",
        "mastercard", "amex", "receipt", "invoice", "qty", "order", "paid", "payment", "thank you",
        "小计", "税", "领收", "領収", "レシート", "quittung", "mwst", "rückgeld", "reçu", "tva", "recibo", "iva",
    ]

    public static func parse(_ text: String?) -> ReceiptFields? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return nil }
        let lowered = text.lowercased()
        guard receiptWords.contains(where: lowered.contains) else { return nil }
        guard let (total, currency) = total(in: lines) else { return nil }
        return ReceiptFields(
            merchant: merchant(in: lines),
            total: total,
            currency: currency ?? currencyCode(in: text)
        )
    }

    /// The amount on the last line that names the total (not a subtotal), or on the
    /// line after it when the amount is printed below.
    static func total(in lines: [String]) -> (Double, String?)? {
        var found: (Double, String?)?
        for (index, line) in lines.enumerated() {
            let lowered = line.lowercased()
            guard totalWords.contains(where: lowered.contains),
                  !lowered.contains("subtotal"), !lowered.contains("sub total"), !lowered.contains("小计")
            else { continue }
            let candidates = [line] + (index + 1 < lines.count ? [lines[index + 1]] : [])
            for candidate in candidates {
                if let amount = amount(in: candidate) {
                    found = (amount, currencyCode(in: candidate))
                    break
                }
            }
        }
        return found
    }

    /// The last amount on a line: "TOTAL $1,234.56" → 1234.56, "Summe 12,50 €" → 12.5.
    static func amount(in line: String) -> Double? {
        let pattern = #/(\d{1,3}(?:[.,]\d{3})*|\d+)(?:([.,])(\d{2}))?(?!\d)/#
        guard let match = line.matches(of: pattern).last else { return nil }
        let whole = String(match.output.1).filter(\.isNumber)
        let cents = match.output.3.map(String.init) ?? "00"
        // A bare number with no decimals and no currency sign is more likely a count.
        if match.output.3 == nil, currencyCode(in: line) == nil { return nil }
        guard let value = Double("\(whole).\(cents)"), value > 0, value < 1_000_000 else { return nil }
        return value
    }

    /// The first line that reads like a name: letters, not a date, number or label.
    static func merchant(in lines: [String]) -> String? {
        let skip = ["receipt", "invoice", "welcome", "tel", "phone", "www.", "http", "order", "date", "table"]
        for line in lines.prefix(6) {
            let lowered = line.lowercased()
            let letters = line.filter(\.isLetter).count
            guard letters >= 2, Double(letters) / Double(line.count) > 0.5, line.count <= 40,
                  !skip.contains(where: lowered.contains)
            else { continue }
            return line
        }
        return nil
    }

    static func currencyCode(in text: String) -> String? {
        let upper = text.uppercased()
        for code in ["USD", "EUR", "GBP", "JPY", "CNY", "RMB", "KRW", "CAD", "AUD", "CHF", "HKD", "SGD", "INR"]
        where upper.contains(code) {
            return code == "RMB" ? "CNY" : code
        }
        if text.contains("€") { return "EUR" }
        if text.contains("£") { return "GBP" }
        if text.contains("₩") { return "KRW" }
        if text.contains("₹") { return "INR" }
        if text.contains("元") { return "CNY" }
        if text.contains("円") || text.contains("¥") { return "JPY" }
        if text.contains("$") { return "USD" }
        return nil
    }
}
