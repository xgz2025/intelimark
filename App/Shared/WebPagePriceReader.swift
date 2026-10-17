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
import Model
import Extraction
import Features
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reads a product page the way a person sees it: loads it in a WebKit view out of
/// sight, lets the shop's scripts run, then asks `laterwisePrice()`
/// (Extensions/Shared/ProductPrice.js) for the price and takes the page's text for a
/// summary. Amazon, Target and Shein state no price to a plain page request. The page
/// uses the app's own web data (`ShopBrowser`), so a shop's "are you a person?" check
/// passed in the shop page sheet stays passed here too.
///
/// WebKit's page process logs a lot while it runs (sandbox, pasteboard, RunningBoard
/// and image-decoding messages). They come from the system, not from Laterwise.
enum WebPagePriceReader {
    /// How long a page may take to show its price.
    static let timeout: Duration = .seconds(20)

    private static let logger = Logger(subsystem: "com.veloworkspaces.nextmark", category: "prices")

    static func read(_ url: URL) async -> RenderedPage? {
        await Gate.shared.run { await render(url) }
    }

    @MainActor
    private static func render(_ url: URL) async -> RenderedPage? {
        guard ShopBrowser.script != nil else { return nil }
        let configuration = ShopBrowser.configuration()
        // Out of sight, but run as if in sight: shops fill the price in with timers.
        configuration.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: pageWidth, height: 2000), configuration: configuration)
        view.customUserAgent = ShopBrowser.userAgent
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
        var price: ShownPrice?
        // Shops fill the price in after loading: ask every second until it's there.
        try? await Task.sleep(for: .seconds(2))
        while ContinuousClock.now < deadline, !Task.isCancelled, !loader.failed {
            price = await ShopBrowser.price(in: view)
            if price != nil { break }
            try? await Task.sleep(for: .seconds(1))
        }
        let text = await pageText(of: view)
        if let price {
            logger.info("Read a price on \(host, privacy: .public) (\(price.origin == .page ? "price element" : "layout", privacy: .public))")
        } else {
            // Why not, for a bug report: a load failure, or the page it got (a sign-in or
            // robot check shows in its title).
            let title = view.title ?? ""
            logger.notice("""
                No price on \(host, privacy: .public): \(loader.failed ? "the page didn't load" : "none shown", privacy: .public); \
                page title “\(title, privacy: .private)”
                """)
            #if DEBUG
            if let found = try? await view.callAsyncJavaScript(Self.clues, arguments: [:], in: nil, contentWorld: .defaultClient) as? String {
                logger.notice("Price clues on \(host, privacy: .public): \(found, privacy: .public)")
            }
            #endif
        }
        guard price != nil || text != nil else { return nil }
        return RenderedPage(price: price, text: text)
    }

    /// The page's words as shown, for a summary when a plain request got none.
    @MainActor
    private static func pageText(of view: WKWebView) async -> String? {
        // The page's main part when it marks one; menus and footers aren't what it's about.
        let script = """
            var main = document.querySelector("main, [role='main'], #dp-container, #ppd");
            var node = main && main.innerText.length > 200 ? main : document.body;
            return node ? node.innerText.slice(0, 8000) : null;
            """
        let text = try? await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String
        let cleaned = text.map(PageText.withoutFurniture)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.count >= 200 ? cleaned : nil
    }

    #if DEBUG
    /// What a page that showed no price has: where it ended up, the price elements the
    /// script looks for, the data it reads, and the amounts in its text.
    private static let clues = """
        var element = document.querySelector("[data-test='product-price'], .productPrice, #productMainPriceId, .a-price .a-offscreen");
        var html = document.documentElement.innerHTML;
        return JSON.stringify({
          url: location.href,
          visibility: document.visibilityState,
          text: document.body ? document.body.innerText.length : 0,
          element: element ? element.outerHTML.slice(0, 300) : null,
          data: ["current_retail", "formatted_current_price", "salePrice", "amountWithSymbol"].filter(function (key) { return html.indexOf(key) >= 0; }),
          amounts: ((document.body && document.body.innerText.match(/[$€£¥]\\s?\\d[\\d.,]*/g)) || []).slice(0, 10)
        });
        """
    #endif

    /// Puts the page in a window nobody sees: WebKit holds back drawing and some scripts
    /// on a page in no window, and shops wait for them to show a price. Returns what
    /// takes it out again.
    @MainActor
    private static func host(_ view: WKWebView) -> () -> Void {
        #if os(macOS)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: pageWidth, height: 2000),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        window.contentView = view
        window.orderBack(nil)
        // Ordering in may move it onto a screen; move it well off them all.
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
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
