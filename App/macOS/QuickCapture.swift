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
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import Observation
import Model
import Capture
import CaptureUI

/// Where a quick capture's content came from.
enum QuickCaptureSource: String, CaseIterable, Identifiable {
    case clipboard, screenshot
    /// Dragged onto the panel; not offered in the picker.
    case dropped

    static let pickable: [QuickCaptureSource] = [.clipboard, .screenshot]

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .clipboard: "Clipboard"
        case .screenshot: "Screenshot"
        case .dropped: "Dropped"
        }
    }

    var symbolName: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .screenshot: "camera.viewfinder"
        case .dropped: "tray.and.arrow.down"
        }
    }
}

/// Opens and closes the quick capture panel (PRD C5) and owns the global hotkey.
/// Captures go through the same envelope path as every other surface.
@MainActor
final class QuickCaptureController {
    static let shared = QuickCaptureController()
    static let hotKeyEnabledKey = "quickCapture.hotKeyEnabled"

    private let store = EnvelopeStore()
    private var panel: QuickCapturePanel?
    private var session: QuickCaptureSession?
    private var hotKey: GlobalHotKey?

    var isHotKeyRegistered: Bool { hotKey != nil }

    /// Registers or removes the hotkey to match the setting (on by default).
    func updateHotKey() {
        let enabled = UserDefaults.standard.object(forKey: Self.hotKeyEnabledKey) as? Bool ?? true
        if enabled, hotKey == nil {
            hotKey = GlobalHotKey(.quickCapture) { [weak self] in self?.toggle() }
        } else if !enabled {
            hotKey?.unregister()
            hotKey = nil
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            session?.cancel()
        } else {
            show()
        }
    }

    func show(source: QuickCaptureSource = .clipboard) {
        session?.cancel()
        // Read before the panel takes focus: this is the app the user was working in.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let session = QuickCaptureSession(store: store, sourceApp: sourceApp) { [weak self] saved in
            self?.finish(saved: saved)
        }
        self.session = session

        let panel = self.panel ?? QuickCapturePanel()
        self.panel = panel
        panel.onCancel = { [weak session] in session?.cancel() }
        panel.contentView = NSHostingView(rootView: QuickCaptureView(session: session))
        panel.setContentSize(NSSize(width: 440, height: 560))
        panel.centerOnScreenUnderPointer()
        panel.makeKeyAndOrderFront(nil)
        session.load(source)
    }

    /// Menu bar → Save Clipboard: saves at once, without the panel.
    func saveClipboard() {
        let id = ULID()
        let snapshot = PasteboardCapture.snapshot(of: .general)
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let store = store
        Task {
            // Copying a large file mustn't stall the menu bar.
            var content = await PasteboardCapture.content(from: snapshot, id: id, store: store)
            guard !content.isEmpty else {
                try? store.discard(id)
                SavedHUD.show(String(localized: "The clipboard is empty"), systemImage: "clipboard")
                return
            }
            content.sourceApp = sourceApp
            do {
                try CaptureWriter.commit(content, id: id, surface: .quickCapture, store: store)
                SavedHUD.show(String(localized: "Saved to Laterwise"))
            } catch {
                try? store.discard(id)
                SavedHUD.show(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func finish(saved: Bool) {
        panel?.orderOut(nil)
        panel?.contentView = nil
        session = nil
        if saved { SavedHUD.show(String(localized: "Saved to Laterwise")) }
    }
}

/// One quick capture: the draft shown in the panel and its payload files.
@MainActor
@Observable
final class QuickCaptureSession {
    let draft = CaptureDraft()
    private(set) var source: QuickCaptureSource = .clipboard
    private(set) var problem: String?
    private(set) var needsScreenRecordingPermission = false
    var isDropTargeted = false

    @ObservationIgnored private var id = ULID()
    private let store: EnvelopeStore
    private let sourceApp: NSRunningApplication?
    private let onFinish: (_ saved: Bool) -> Void
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var isFinished = false

    init(store: EnvelopeStore, sourceApp: NSRunningApplication?, onFinish: @escaping (_ saved: Bool) -> Void) {
        self.store = store
        self.sourceApp = sourceApp
        self.onFinish = onFinish
    }

    func load(_ source: QuickCaptureSource) {
        guard source != .dropped else { return }
        startOver(with: source)
        switch source {
        case .clipboard:
            let snapshot = PasteboardCapture.snapshot(of: .general)
            let (id, store) = (id, store)
            loading = Task {
                let content = await PasteboardCapture.content(from: snapshot, id: id, store: store)
                // Replaced or cancelled while copying: the copy recreated the discarded folder.
                guard !Task.isCancelled else { try? store.discard(id); return }
                show(content)
            }
        case .screenshot:
            let display = ScreenshotCapture.displayUnderPointer()
            let id = id
            loading = Task {
                do {
                    let png = try await ScreenshotCapture.capturePNG(of: display)
                    guard !Task.isCancelled else { return }
                    let file = try store.addPayload(png, fileName: "0-screenshot.png", contentType: .png, for: id)
                    draft.thumbnail = NSImage(data: png).map { Image(nsImage: $0) }
                    show(SharedContent(title: screenshotTitle, files: [file]))
                } catch {
                    guard !Task.isCancelled else { return }
                    problem = error.localizedDescription
                    needsScreenRecordingPermission = (error as? ScreenshotCapture.Failure) == .permissionNeeded
                    show(SharedContent())
                }
            }
        case .dropped:
            break
        }
    }

    /// Links, files and images dragged onto the panel replace its content.
    func drop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        startOver(with: .dropped)
        let snapshot = PasteboardCapture.Snapshot(
            fileURLs: urls.filter(\.isFileURL), url: urls.first { !$0.isFileURL }
        )
        let (id, store) = (id, store)
        loading = Task {
            let content = await PasteboardCapture.content(from: snapshot, id: id, store: store)
            let thumbnail = content.files.count == 1 ? await Self.thumbnail(of: snapshot.fileURLs.first) : nil
            // Replaced or cancelled while copying: the copy recreated the discarded folder.
            guard !Task.isCancelled else { try? store.discard(id); return }
            draft.thumbnail = thumbnail.map { Image(decorative: $0, scale: 1) }
            show(content)
        }
        return true
    }

    /// A small preview of a dropped image, made without reading the whole file.
    private nonisolated static func thumbnail(of url: URL?) async -> sending CGImage? {
        guard let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    func save() {
        guard !isFinished, var content = draft.content, !content.isEmpty else { return }
        content.sourceApp = content.sourceApp ?? sourceApp?.bundleIdentifier
        do {
            try CaptureWriter.commit(
                content, id: id, surface: .quickCapture,
                intent: draft.intent, note: draft.trimmedNote, store: store
            )
            isFinished = true
            onFinish(true)
        } catch {
            problem = error.localizedDescription
        }
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        loading?.cancel()
        try? store.discard(id)
        onFinish(false)
    }

    /// Drops whatever was loaded before, including its payload files.
    private func startOver(with source: QuickCaptureSource) {
        loading?.cancel()
        try? store.discard(id)
        id = ULID()
        self.source = source
        problem = nil
        needsScreenRecordingPermission = false
        draft.thumbnail = nil
        draft.content = nil
        draft.isLoading = true
    }

    private func show(_ content: SharedContent) {
        draft.content = content
        draft.isLoading = false
    }

    private var screenshotTitle: String {
        if let name = sourceApp?.localizedName {
            return String(localized: "Screenshot of \(name)")
        }
        return String(localized: "Screenshot")
    }
}

/// A floating panel that takes keyboard focus without bringing Laterwise's other
/// windows forward, like Spotlight. Esc cancels.
final class QuickCapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        title = String(localized: "Quick Capture")
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    func centerOnScreenUnderPointer() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else {
            center()
            return
        }
        let visible = screen.visibleFrame
        // A little above the middle, where the eye goes first.
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + visible.height * 0.08))
    }
}

struct QuickCaptureView: View {
    @Bindable var session: QuickCaptureSession

    var body: some View {
        CaptureSheet(draft: session.draft, onSave: { session.save() }, onCancel: { session.cancel() }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Source", selection: Binding(get: { session.source }, set: { session.load($0) })) {
                    ForEach(QuickCaptureSource.pickable) { source in
                        Label(source.title, systemImage: source.symbolName).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let problem = session.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                    if session.needsScreenRecordingPermission, let url = ScreenshotCapture.privacySettingsURL {
                        Button("Open Privacy Settings…") { NSWorkspace.shared.open(url) }
                    }
                } else {
                    Text("Or drop a link, file or image on this panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 440, height: 560)
        .dropDestination(for: URL.self) { urls, _ in
            session.drop(urls)
        } isTargeted: { targeted in
            session.isDropTargeted = targeted
        }
        .overlay {
            if session.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }
}
