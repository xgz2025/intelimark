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
import Model

/// What a photo's own metadata says: when and where it was taken (EXIF and GPS).
public enum PhotoMetadata {
    public static func read(from url: URL) -> PhotoFields? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(read(from:))
    }

    public static func read(from data: Data) -> PhotoFields? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(read(from:))
    }

    static func read(from source: CGImageSource) -> PhotoFields? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return fields(from: properties)
    }

    static func fields(from properties: [CFString: Any]) -> PhotoFields? {
        var fields = PhotoFields()
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W"
            let lat = south ? -latitude : latitude
            let lon = west ? -longitude : longitude
            // 0,0 is what some apps write when they have no location.
            if (-90...90).contains(lat), (-180...180).contains(lon), lat != 0 || lon != 0 {
                fields.latitude = lat
                fields.longitude = lon
            }
        }
        fields.takenAt = takenAt(in: properties)
        return fields == PhotoFields() ? nil : fields
    }

    /// When the picture was taken, by the camera's own clock: the original time, else
    /// when it was digitized (scans), else the file's TIFF time (some editors keep only that).
    static func takenAt(in properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let candidates: [(String?, String?)] = [
            (exif[kCGImagePropertyExifDateTimeOriginal] as? String, exif[kCGImagePropertyExifOffsetTimeOriginal] as? String),
            (exif[kCGImagePropertyExifDateTimeDigitized] as? String, exif[kCGImagePropertyExifOffsetTimeDigitized] as? String),
            (tiff[kCGImagePropertyTIFFDateTime] as? String, exif[kCGImagePropertyExifOffsetTime] as? String),
        ]
        for case let (text?, offset) in candidates {
            if let date = date(text, offset: offset) { return date }
        }
        return nil
    }

    /// EXIF dates read "2026:10:03 18:42:07", in the camera's local time; the offset
    /// ("+09:00") says which, when the camera wrote it.
    static func date(_ text: String, offset: String?) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        // Cameras without a clock write zeros.
        guard !text.hasPrefix("0000") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            return formatter.date(from: text + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: text)
    }
}

#if canImport(PDFKit)
import PDFKit

/// A PDF's own title and author, from its document info.
public enum PDFMetadata {
    public static func read(from url: URL) -> ArticleFields? {
        PDFDocument(url: url).flatMap(read(from:))
    }

    public static func read(from data: Data) -> ArticleFields? {
        PDFDocument(data: data).flatMap(read(from:))
    }

    static func read(from document: PDFDocument) -> ArticleFields? {
        let attributes = document.documentAttributes ?? [:]
        func text(_ key: PDFDocumentAttribute) -> String? {
            guard let value = (attributes[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty, !isPlaceholder(value)
            else { return nil }
            return value
        }
        let fields = ArticleFields(
            headline: text(.titleAttribute),
            author: text(.authorAttribute),
            publishedAt: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        )
        return fields.headline == nil && fields.author == nil ? nil : fields
    }

    /// Titles tools fill in on their own: "Microsoft Word - draft.docx", "untitled".
    static func isPlaceholder(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("microsoft word - ") || lowered == "untitled" || lowered.hasSuffix(".docx")
            || lowered.hasSuffix(".doc") || lowered.hasSuffix(".pdf")
    }
}
#endif

/// Names a place from coordinates ("Shibuya, Tokyo").
public protocol PlaceNaming: Sendable {
    func name(latitude: Double, longitude: Double) async -> String?
}

#if canImport(MapKit)
import MapKit

/// Apple Maps reverse geocoding. Only coordinates are sent, only for photos that
/// carry them, and only once per photo.
public struct MapKitPlaceNamer: PlaceNaming {
    static let timeLimit: TimeInterval = 10

    public init() {}

    public func name(latitude: Double, longitude: Double) async -> String? {
        try? await withTimeLimit(Self.timeLimit) {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try await request.mapItems.first
            else { return nil }
            return item.address?.shortAddress ?? item.name
        }
    }
}
#endif
