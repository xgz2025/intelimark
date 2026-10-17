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

/// The File and Edit menu commands (Mac, and an iPad's keyboard): New Note or Link
/// ⌘N, New Group ⇧⌘N, Find ⌘F, and the sidebar toggle.
public struct LibraryCommands: Commands {
    let navigator: AppNavigator
    /// Brings the library window forward first (on the Mac it may be closed).
    let showLibrary: @MainActor () -> Void

    public init(navigator: AppNavigator, showLibrary: @escaping @MainActor () -> Void = {}) {
        self.navigator = navigator
        self.showLibrary = showLibrary
    }

    public var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .newItem) {
            Button("New Note or Link…") { run(.newNote) }
                .keyboardShortcut("n")
            Button("New Group…") { run(.newGroup) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Library") { run(.search) }
                .keyboardShortcut("f")
        }
    }

    private func run(_ command: AppNavigator.Command) {
        showLibrary()
        navigator.perform(command)
    }
}
