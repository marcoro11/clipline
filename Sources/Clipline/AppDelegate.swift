import AppKit
import Combine
import SwiftUI

/// Clicking a slot must leave keyboard focus in the user's destination app.
final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ClipboardController!
    private var panel: StickyPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = ClipboardController()
        makeMainMenu()
        makePanel()
        makeStatusItem()
        controller.showPanel = { [weak self] in self?.showPanel() }
        controller.settingsChanged = { [weak self] in self?.updateAppearance() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showPanel),
            name: Notification.Name("app.clipline.mac.show-panel"), object: nil)
        controller.store.$slots.sink { [weak self] slots in
            let count = slots.filter { $0.payload != nil }.count
            self?.statusItem.button?.title = count > 0 ? " \(count)" : ""
            self?.statusItem.button?.toolTip = "Clipline · \(count) of \(slots.count) slots waiting"
        }.store(in: &subscriptions)
        controller.$hasAccessibility.combineLatest(controller.$shortcutError, controller.$permissionWasRequested)
            .dropFirst().sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.resizePanel() }
            }.store(in: &subscriptions)
        showPanel()
    }

    private func makePanel() {
        panel = StickyPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 590),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Clipline"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        let view = SlotPanelView(controller: controller, store: controller.store,
            openSettings: { [weak self] in self?.openSettings() },
            hide: { [weak self] in self?.panel.orderOut(nil) })
        let host = PanelHostingView(rootView: view)
        panel.contentView = host
        let size = host.fittingSize
        panel.setContentSize(size)
        if !panel.setFrameUsingName("CliplineStickyPanel") {
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 28, y: frame.maxY - size.height - 28))
            }
        }
        panel.setFrameAutosaveName("CliplineStickyPanel")
        updateAppearance()
    }

    private func updateAppearance() {
        panel?.alphaValue = controller.settings.opacity
        panel?.appearance = controller.settings.theme.appearance
        settingsWindow?.appearance = controller.settings.theme.appearance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.resizePanel() }
    }

    private func resizePanel() {
        guard let panel, let view = panel.contentView else { return }
        let top = panel.frame.maxY
        panel.setContentSize(view.fittingSize)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Clipline")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Show Clipline", action: #selector(showPanel), keyEquivalent: "")
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            let clear = menu.addItem(withTitle: "Clear All Slots", action: #selector(clearAllSlots), keyEquivalent: "")
            clear.isEnabled = !controller.isBusy && controller.store.occupiedCount > 0
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Clipline", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            menu.autoenablesItems = false
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    @objc private func showPanel() {
        // Do not activate Clipline: the active app is the copy/paste destination.
        panel.orderFrontRegardless()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Clipline Settings"
            window.isReleasedWhenClosed = false
            window.level = .floating
            settingsWindow = window
        }
        guard let window = settingsWindow else { return }
        window.appearance = controller.settings.theme.appearance
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller) { [weak window] in
            window?.close()
        })
        if let size = window.contentView?.fittingSize { window.setContentSize(size) }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func clearAllSlots() { controller.clearAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func makeMainMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        menu.addItem(app)
        let submenu = NSMenu()
        submenu.addItem(withTitle: "About Clipline", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        let settings = submenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Clipline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = submenu
        NSApp.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.refreshAccessibility()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }
}
