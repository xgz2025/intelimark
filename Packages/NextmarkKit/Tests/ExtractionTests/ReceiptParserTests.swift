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
import ImageIO
import Testing
import Model
@testable import Extraction

struct ReceiptParserTests {
    @Test func readsMerchantAndTotal() throws {
        let text = """
            Blue Bottle Coffee
            1 Ferry Building
            Latte              5.50
            Croissant          4.25
            Subtotal           9.75
            Tax                0.86
            TOTAL             $10.61
            VISA ****1234
            """
        let receipt = try #require(ReceiptParser.parse(text))
        #expect(receipt.merchant == "Blue Bottle Coffee")
        #expect(receipt.total == 10.61)
        #expect(receipt.currency == "USD")
    }

    @Test func readsEuropeanAmountsAndAmountsBelowTheirLabel() throws {
        let text = """
            Bäckerei Schmidt
            Brötchen 2x      1,20
            Summe
            12,50 €
            Bar              20,00
            Rückgeld          7,50
            MwSt 7%
            """
        let receipt = try #require(ReceiptParser.parse(text))
        #expect(receipt.total == 12.5)
        #expect(receipt.currency == "EUR")
        #expect(receipt.merchant == "Bäckerei Schmidt")
    }

    @Test func ignoresTextThatIsntAReceipt() {
        #expect(ReceiptParser.parse("Meeting notes\nTotal attendance was great\nNext steps") == nil)
        #expect(ReceiptParser.parse("Concert\nSat Oct 3\nDoors 7pm") == nil)
        #expect(ReceiptParser.parse(nil) == nil)
    }

    @Test func largeAmountsKeepTheirThousands() {
        #expect(ReceiptParser.amount(in: "Grand Total USD 1,234.56") == 1234.56)
        #expect(ReceiptParser.amount(in: "Total 1.234,56 €") == 1234.56)
        #expect(ReceiptParser.amount(in: "Total items 3") == nil)
    }
}

struct PhotoMetadataTests {
    @Test func readsLocationAndTimeTaken() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 35.6595, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 139.7005, kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:03 18:42:07",
                kCGImagePropertyExifOffsetTimeOriginal: "+09:00",
            ] as [CFString: Any],
        ]
        let photo = try #require(PhotoMetadata.fields(from: properties))
        #expect(photo.latitude == 35.6595)
        #expect(photo.longitude == 139.7005)
        #expect(photo.takenAt == Date(timeIntervalSince1970: 1_791_020_527))
    }

    @Test func westAndSouthAreNegativeAndZeroIsNoLocation() {
        let west: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.86, kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.21, kCGImagePropertyGPSLongitudeRef: "W",
            ] as [CFString: Any],
        ]
        #expect(PhotoMetadata.fields(from: west)?.latitude == -33.86)
        #expect(PhotoMetadata.fields(from: west)?.longitude == -151.21)
        let zero: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0.0, kCGImagePropertyGPSLongitude: 0.0] as [CFString: Any],
        ]
        #expect(PhotoMetadata.fields(from: zero) == nil)
    }
}
