import AppKit
import SwiftUI

/// Renders our own views with sample data, without opening windows or reading
/// the user's screen, clipboard, or saved settings into the rendered content.
enum PreviewRenderer {
    @MainActor
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for (theme, count, suffix) in [(AppTheme.light, 5, ""), (.dark, 10, "-dark")] {
            var settings = AppSettings()
            settings.theme = theme
            settings.slotCount = count
            let controller = ClipboardController(settings: settings, registerHotKeys: false,
                                                 permissionCheck: { true }, persistSettings: { _ in })
            for (index, text) in [
                (0, "A little room for your clipboard."),
                (1, "https://example.com/design-notes"),
                (3, "Pick up where you left off.\nKeep the good ideas close.")
            ] {
                board.clearContents()
                board.setString(text, forType: .string)
                if let payload = ClipboardPayload(pasteboard: board) { controller.store.save(payload, at: index) }
            }
            let panel = SlotPanelView(controller: controller, store: controller.store, openSettings: {}, hide: {})
            try snapshot(panel, appearance: theme.appearance,
                         to: directory.appendingPathComponent("panel\(suffix).png"))
            try snapshot(SettingsView(controller: controller, close: {}), appearance: theme.appearance,
                         to: directory.appendingPathComponent("settings\(suffix).png"))
        }
        print("Rendered light and dark panel/settings previews in \(directory.path)")
    }

    @MainActor
    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance?, to url: URL) throws {
        // Hosting in an offscreen window also renders AppKit-backed controls,
        // which SwiftUI's ImageRenderer replaces with unsupported-view symbols.
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = appearance
        window.backgroundColor = .clear
        window.isOpaque = false
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "CliplinePreview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render \(url.lastPathComponent)"])
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CliplinePreview", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not encode preview PNG"])
        }
        try data.write(to: url)
        withExtendedLifetime(window) {}
    }
}
