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

/// Laterwise's pages on the web.
enum NextmarkLinks {
    static let website = URL(string: "https://www.veloworkspaces.com/laterwise/")!
    static let support = URL(string: "https://www.veloworkspaces.com/laterwise/support/")!
    static let privacy = URL(string: "https://www.veloworkspaces.com/laterwise/privacy/")!
    /// Apple's standard licence agreement, which Laterwise uses.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let feedbackAddress = "laterwise@veloworkspaces.com"

    /// Laterwise's App Store ID: the number in its App Store link (App Store Connect ›
    /// App Information › Apple ID).
    static let appStoreID: String? = "6822739724"

    static var appStore: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") }
    }

    /// Opens the App Store straight at "Write a Review".
    static var writeReview: URL? {
        appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)?action=write-review") }
    }

    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// An email to us, with what helps answer it already filled in.
    static var feedbackMail: URL {
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Laterwise \(versionDescription)"),
            URLQueryItem(name: "body", value: "\n\n—\nNextmark \(versionDescription), \(system)"),
        ]
        return components.url ?? URL(string: "mailto:\(feedbackAddress)")!
    }
}

/// Open-source software in Laterwise and its licence, as the licence asks.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    static let notices: [(name: String, url: URL, license: String)] = [
        (
            "GRDB.swift",
            URL(string: "https://github.com/groue/GRDB.swift")!,
            """
            Copyright (C) 2015-2025 Gwendal Roué

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and \
            associated documentation files (the "Software"), to deal in the Software without restriction, including \
            without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
            copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the \
            following conditions:

            The above copyright notice and this permission notice shall be included in all copies or substantial \
            portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT \
            LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO \
            EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER \
            IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR \
            THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            """
        ),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.notices, id: \.name) { notice in
                    Section {
                        Text(verbatim: notice.license)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Link(notice.name, destination: notice.url)
                    } footer: {
                        Text("MIT License")
                    }
                }
            }
            .navigationTitle("Acknowledgements")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }
}
