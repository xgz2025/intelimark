//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import AppKit
import SwiftUI
import Features

/// Menu commands that bring the library window back first: on the Mac it's often
/// closed while Laterwise keeps running in the menu bar.
struct MacLibraryCommands: Commands {
    let navigator: AppNavigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        LibraryCommands(navigator: navigator) {
            openWindow(id: NextmarkApp.mainWindowID)
            NSApplication.shared.activate()
        }
    }
}

extension View {
    /// Lets the app model open the library window from outside any view, e.g. when
    /// a notification is clicked with the window closed.
    func opensLibraryWindow(for model: AppModel) -> some View {
        modifier(LibraryWindowOpener(model: model))
    }
}

private struct LibraryWindowOpener: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let open = openWindow
            model.showLibrary = {
                open(id: NextmarkApp.mainWindowID)
                NSApplication.shared.activate()
            }
        }
    }
}
