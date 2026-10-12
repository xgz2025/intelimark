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
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Small JPEG previews of images and the first page of PDFs, for lists and for
/// devices that don't have the original (PRD P2: thumbnails always sync).
public enum Thumbnailer {
    public static let fileName = "thumbnail.jpg"
    public static let maxPixelSize = 600

    /// Writes a thumbnail of `file` to `destination`. Returns its size in bytes, or nil
    /// for a file that isn't an image or a PDF, or can't be drawn.
    @discardableResult
    public static func write(from file: LocalFile, to destination: URL, maxPixelSize: Int = maxPixelSize) -> Int64? {
        guard let image = image(for: file, maxPixelSize: maxPixelSize),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary
        CGImageDestinationAddImage(output, image, options)
        guard CGImageDestinationFinalize(output) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    static func image(for file: LocalFile, maxPixelSize: Int) -> CGImage? {
        guard let type = UTType(file.contentType) else { return nil }
        if type.conforms(to: .pdf) {
            return firstPage(of: file.url, maxPixelSize: maxPixelSize)
        }
        guard type.conforms(to: .image), let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    static func firstPage(of url: URL, maxPixelSize: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        var size = page.getBoxRect(.cropBox).size
        if page.rotationAngle % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(maxPixelSize) / max(size.width, size.height)
        let width = max(1, Int(size.width * scale))
        let height = max(1, Int(size.height * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
