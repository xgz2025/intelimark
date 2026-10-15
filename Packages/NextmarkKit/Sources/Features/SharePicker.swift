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

extension View {
    /// The system share sheet for `items`, shown from this view when `isPresented`
    /// turns true. Unlike `ShareLink`, it leaves out Laterwise's own Share extension:
    /// saving something to the library it's already in makes no sense.
    func sharePicker(isPresented: Binding<Bool>, items: [URL]) -> some View {
        background(SharePickerAnchor(isPresented: isPresented, items: items))
    }
}

enum OwnShareExtension {
    /// The Share extension's bundle ID, which is also its activity type on iOS.
    static var bundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.veloworkspaces.nextmark") + ".share"
    }

    /// What the extension is called in a share menu.
    static var names: Set<String> {
        let info = Bundle.main.localizedInfoDictionary ?? Bundle.main.infoDictionary ?? [:]
        let display = [info["CFBundleDisplayName"], info["CFBundleName"]].compactMap { $0 as? String }
        return Set(display + ["Laterwise"])
    }
}

#if os(iOS)
import UIKit

private struct SharePickerAnchor: UIViewRepresentable {
    @Binding var isPresented: Bool
    let items: [URL]

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard isPresented else { return }
        // State can't change during an update: reset it right after.
        Task { @MainActor in isPresented = false }
        guard !items.isEmpty, var presenter = view.window?.rootViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = [UIActivity.ActivityType(rawValue: OwnShareExtension.bundleIdentifier)]
        // iPad: a popover from where the person tapped.
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = view.bounds
        presenter.present(controller, animated: true)
    }
}
#elseif os(macOS)
import AppKit

private struct SharePickerAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [URL]

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard isPresented else { return }
        Task { @MainActor in isPresented = false }
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        /// Kept while the menu is open.
        var picker: NSSharingServicePicker?

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            sharingServicesForItems items: [Any],
            proposedSharingServices proposedServices: [NSSharingService]
        ) -> [NSSharingService] {
            let names = OwnShareExtension.names
            let identifier = OwnShareExtension.bundleIdentifier
            return proposedServices.filter { service in
                !names.contains(service.title) && !service.name.rawValue.contains(identifier)
            }
        }
    }
}
#endif
