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
import Photos
import Library

/// Screenshots from the Photos library (the Screenshots smart album).
public struct PhotosScreenshotSource: ScreenshotSource {
    public init() {}

    public func access() -> PhotosAccess {
        Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> PhotosAccess {
        Self.access(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    static func access(_ status: PHAuthorizationStatus) -> PhotosAccess {
        switch status {
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public func screenshots() async -> [ScreenshotRef] {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        guard let album = albums.firstObject else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(in: album, options: options)
        return (0..<assets.count).map { index in
            let asset = assets.object(at: index)
            return ScreenshotRef(id: asset.localIdentifier, takenAt: asset.creationDate ?? .distantPast)
        }
    }

    public func load(_ screenshot: ScreenshotRef) async -> ImportedScreenshot? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [screenshot.id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true       // iCloud Photos may keep only a preview on the device
        options.deliveryMode = .highQualityFormat
        options.version = .current
        // Downloading from iCloud can take long: cancelling (the background task
        // expired, the user stopped it) cancels the request, which then returns nothing.
        let request = ImageRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let id = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, type, _, _ in
                    guard let data, let type else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: ImportedScreenshot(
                        assetID: screenshot.id, data: data, contentType: type, takenAt: screenshot.takenAt
                    ))
                }
                request.started(id)
            }
        } onCancel: {
            request.cancel()
        }
    }

    public func delete(_ ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }
}

/// A Photos request that may be cancelled from another thread, before or after it starts.
private final class ImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var id: PHImageRequestID?
    private var isCancelled = false

    func started(_ id: PHImageRequestID) {
        let cancelNow = lock.withLock {
            self.id = id
            return isCancelled
        }
        if cancelNow { PHImageManager.default().cancelImageRequest(id) }
    }

    func cancel() {
        let id = lock.withLock {
            isCancelled = true
            return self.id
        }
        if let id { PHImageManager.default().cancelImageRequest(id) }
    }
}
