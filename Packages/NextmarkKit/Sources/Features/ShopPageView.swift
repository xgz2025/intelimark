//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import WebKit
import Model
import Library
import Extraction

/// How Laterwise opens shops' pages: as Safari, with the price script
/// (Extensions/Shared/ProductPrice.js, bundled with the app). Pages share the app's own
/// web data (not Safari's), so a "are you a person?" check passed once stays passed.
public enum ShopBrowser {
    public static let script: String? = Bundle.main.url(forResource: "ProductPrice", withExtension: "js")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    public static var userAgent: String {
        #if os(iOS)
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
        #else
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        #endif
    }

    /// A page's configuration: the app's web data, media only on request.
    @MainActor
    public static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        return configuration
    }

    /// The price the page shows now, if any.
    @MainActor
    public static func price(in view: WKWebView) async -> ShownPrice? {
        guard let script else { return nil }
        // In Laterwise's own script world: the page's scripts can't see or change it.
        let result = try? await view.callAsyncJavaScript(
            script + "\nreturn laterwisePrice();", arguments: [:], in: nil, contentWorld: .defaultClient
        )
        return result.flatMap { ShownPrice(script: $0) }
    }
}

/// The shop's page inside Laterwise, for when reading it out of sight isn't enough: the
/// shop wants to check you're a person, or shows the price only once you pick a size or
/// sign in. The person deals with the page; Laterwise reads the price it shows.
struct ShopPageSheet: View {
    let item: ItemRecord
    let url: URL
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var page = ShopPage()

    private var currency: String? { page.price?.currency ?? item.typedFields?.product?.currency }

    var body: some View {
        NavigationStack {
            ShopWebView(view: page.view)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    status
                }
                .navigationTitle(url.host() ?? "")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(useTitle) { use() }
                            .disabled(page.price == nil)
                    }
                }
        }
        .task {
            page.load(url)
            await page.watch()
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 700)
        #endif
    }

    private var useTitle: String {
        guard let price = page.price else { return String(localized: "Use Price") }
        return String(localized: "Use \(ItemRecord.money(price.price, currency: currency))")
    }

    private var status: some View {
        HStack(spacing: 8) {
            if let price = page.price {
                Image(systemName: "tag.fill").foregroundStyle(.green)
                Text("Laterwise sees \(ItemRecord.money(price.price, currency: currency)) on this page. Pick a size or color first if the price depends on it.")
            } else {
                ProgressView().controlSize(.small)
                Text("Looking for the price… If the shop asks whether you're a person, answer it here.")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func use() {
        guard let price = page.price else { return }
        let (items, id, currency) = (services.items, item.id, currency)
        // Seen and chosen by the person: theirs.
        performEdit { _ = try await items.recordPrice(price.price, currency: currency, origin: .user, forItem: id) }
        dismiss()
    }
}

/// A shop's page and the price it shows, read every second or so.
@MainActor
@Observable
final class ShopPage {
    @ObservationIgnored let view: WKWebView
    private(set) var price: ShownPrice?

    init() {
        view = WKWebView(frame: .zero, configuration: ShopBrowser.configuration())
        view.customUserAgent = ShopBrowser.userAgent
        view.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        guard view.url == nil else { return }
        view.load(URLRequest(url: url))
    }

    func watch() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            if let found = await ShopBrowser.price(in: view) {
                price = found
            }
        }
    }
}

#if os(macOS)
private struct ShopWebView: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
private struct ShopWebView: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
