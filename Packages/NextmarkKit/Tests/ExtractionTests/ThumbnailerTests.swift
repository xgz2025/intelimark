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
import ImageIO
@testable import Extraction

struct ThumbnailerTests {
    func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func imagesShrinkToFit() throws {
        let directory = try Fixtures.temporaryDirectory()
        let original = directory.appending(path: "0-receipt.png")
        try Fixtures.makePNG(text: "Total 42.00", at: original)
        let thumbnail = directory.appending(path: Thumbnailer.fileName)

        let size = try #require(Thumbnailer.write(from: LocalFile(url: original, contentType: "public.png"), to: thumbnail))
        #expect(size > 0)
        let pixels = try pixelSize(of: thumbnail)
        #expect(pixels.width == Thumbnailer.maxPixelSize)       // 1400 × 320 → 600 wide
        #expect(pixels.height < pixels.width)
    }

    @Test func pdfsShowTheirFirstPage() throws {
        let directory = try Fixtures.temporaryDirectory()
        let original = directory.appending(path: "0-menu.pdf")
        try Fixtures.makePDF(text: "Menu", at: original)
        let thumbnail = directory.appending(path: Thumbnailer.fileName)

        #expect(Thumbnailer.write(from: LocalFile(url: original, contentType: "com.adobe.pdf"), to: thumbnail) != nil)
        let pixels = try pixelSize(of: thumbnail)
        #expect(pixels.height == Thumbnailer.maxPixelSize)      // portrait letter page
        #expect(pixels.width < pixels.height)
    }

    @Test func otherFilesHaveNoThumbnail() throws {
        let directory = try Fixtures.temporaryDirectory()
        let original = directory.appending(path: "0-notes.txt")
        try Data("notes".utf8).write(to: original)
        let thumbnail = directory.appending(path: Thumbnailer.fileName)
        #expect(Thumbnailer.write(from: LocalFile(url: original, contentType: "public.plain-text"), to: thumbnail) == nil)
    }
}
