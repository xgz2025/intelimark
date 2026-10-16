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
import OSLog
import WebKit
import Extraction
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reads a product's price the way a person sees it: loads the page in an offscreen
/// WebKit view, lets the shop's scripts run, then asks `laterwisePrice()`
/// (Extensions/Shared/ProductPrice.js). Amazon, Target and Shein state no price to a
/// plain page request. Only the page is requested, with no cookies or sign-in: a
/// separate, non-persistent website data store.
///
/// WebKit's page process logs a lot while it runs (sandbox, pasteboard, RunningBoard
/// and image-decoding messages). They come from the system, not from Laterwise.
enum WebPagePriceReader {
    /// How long a page may take to show its price.
    static let timeout: Duration = .seconds(20)

    static let script: String? = Bundle.main.url(forResource: "ProductPrice", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    private static let logger = Logger(subsystem: "com.veloworkspaces.nextmark", category: "prices")

    static func price(at url: URL) async -> ShownPrice? {
        await Gate.shared.run { await read(url) }
    }

    @MainActor
    private static func read(_ url: URL) async -> ShownPrice? {
        guard let script else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Out of sight, but run as if in sight: shops fill the price in with timers.
        configuration.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: pageWidth, height: 2000), configuration: configuration)
        // The shop's page for Safari, as a person would get it.
        view.customUserAgent = userAgent
        let loader = Loader()
        view.navigationDelegate = loader
        let unhost = host(view)
        defer {
            view.stopLoading()
            view.navigationDelegate = nil
            unhost()
        }
        view.load(URLRequest(url: url, timeoutInterval: 15))
        let host = url.host() ?? "?"
        let deadline = ContinuousClock.now.advanced(by: timeout)
        // Shops fill the price in after loading: ask every second until it's there.
        try? await Task.sleep(for: .seconds(2))
        while ContinuousClock.now < deadline, !Task.isCancelled, !loader.failed {
            // In Laterwise's own script world: the page's scripts can't see or change it.
            if let result = try? await view.callAsyncJavaScript(
                script + "\nreturn laterwisePrice();", arguments: [:], in: nil, contentWorld: .defaultClient
            ), let price = ShownPrice(script: result) {
                logger.info("Read a price on \(host, privacy: .public) (\(price.origin == .page ? "price element" : "layout", privacy: .public))")
                return price
            }
            try? await Task.sleep(for: .seconds(1))
        }
        // Why not, for a bug report: a load failure, or the page it got (a sign-in or
        // robot check shows in its title).
        let title = view.title ?? ""
        logger.notice("""
            No price on \(host, privacy: .public): \(loader.failed ? "the page didn't load" : "none shown", privacy: .public); \
            page title “\(title, privacy: .private)”
            """)
        return nil
    }

    /// Puts the page in a window, out of sight: WebKit holds back drawing and some
    /// scripts on a page in no window, and shops wait for them to show a price.
    /// Returns what takes it out again.
    @MainActor
    private static func host(_ view: WKWebView) -> () -> Void {
        #if os(macOS)
        let window = NSWindow(
            contentRect: NSRect(x: -30_000, y: -30_000, width: pageWidth, height: 2000),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        window.contentView = view
        window.orderBack(nil)
        return {
            window.orderOut(nil)
            window.contentView = nil
        }
        #else
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return {} }
        view.frame = CGRect(x: -10_000, y: 0, width: pageWidth, height: 2000)
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        window.insertSubview(view, at: 0)
        return { view.removeFromSuperview() }
        #endif
    }

    private static var pageWidth: CGFloat {
        #if os(iOS)
        390
        #else
        1280
        #endif
    }

    private static var userAgent: String {
        #if os(iOS)
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
        #else
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        #endif
    }

    /// Notes a page that failed to load, so the reader stops waiting for it.
    @MainActor
    private final class Loader: NSObject, WKNavigationDelegate {
        var failed = false

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            failed = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            failed = true
        }
    }

    /// One page at a time: a group's Check Prices would otherwise open a page per product.
    private actor Gate {
        static let shared = Gate()
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T {
            if busy {
                await withCheckedContinuation { waiting.append($0) }
            }
            busy = true
            let result = await work()
            if waiting.isEmpty {
                busy = false
            } else {
                waiting.removeFirst().resume()
            }
            return result
        }
    }
}
