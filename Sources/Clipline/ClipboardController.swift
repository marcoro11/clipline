import AppKit
import Carbon.HIToolbox
import Combine
import OSLog

final class ClipboardController: ObservableObject {
    let store: SlotStore
    @Published private(set) var settings: AppSettings
    @Published private(set) var message = "Copy a little. Keep your flow."
    @Published private(set) var isError = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var permissionWasRequested = false
    @Published private(set) var isRepairingPermission = false
    @Published var shortcutError: String?
    @Published private var lastPaste: (index: Int, payload: ClipboardPayload)?
    var showPanel: (() -> Void)?
    var settingsChanged: (() -> Void)?

    private let hotKeys: HotKeyManager?
    private let permissionCheck: () -> Bool
    private let persistSettings: (AppSettings) -> Void
    private let permissionRequest: () -> Void
    private let showPermissionSettings: () -> Void
    private let permissionRepair: (@escaping (String?) -> Void) -> Void
    private var permissionTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var messageIsPermissionError = false
    private var messageID = UUID()
    private var pendingActions: [(action: SlotAction, process: pid_t)] = []
    private let permissionLog = Logger(subsystem: "app.clipline.mac", category: "permissions")

    var canUndoPaste: Bool {
        guard let lastPaste else { return false }
        return !isBusy && lastPaste.index < store.capacity && store.payload(at: lastPaste.index) == nil
    }

    func undoPaste() {
        guard canUndoPaste, let lastPaste else { return }
        store.save(lastPaste.payload, at: lastPaste.index)
        self.lastPaste = nil
        report("Restored slot \(lastPaste.index + 1)")
    }

    func clearAll() {
        guard !isBusy else { return }
        store.clearAll()
        lastPaste = nil
        report("All \(store.capacity) slots are ready.")
    }

    init(settings initialSettings: AppSettings = AppSettings.load(), registerHotKeys: Bool = true,
         permissionCheck: @escaping () -> Bool = AccessibilityPermission.isGranted,
         persistSettings: @escaping (AppSettings) -> Void = { $0.save() },
         permissionRequest: @escaping () -> Void = AccessibilityPermission.request,
         showPermissionSettings: @escaping () -> Void = AccessibilityPermission.openSettings,
         permissionRepair: @escaping (@escaping (String?) -> Void) -> Void = AccessibilityPermission.repair) {
        let initial = initialSettings.validationError == nil ? initialSettings : AppSettings()
        self.settings = initial
        self.store = SlotStore(capacity: initial.slotCount)
        self.permissionCheck = permissionCheck
        self.persistSettings = persistSettings
        self.permissionRequest = permissionRequest
        self.showPermissionSettings = showPermissionSettings
        self.permissionRepair = permissionRepair
        hotKeys = registerHotKeys ? HotKeyManager() : nil
        hasAccessibility = permissionCheck()
        if registerHotKeys {
            permissionLog.notice("Clipline event posting allowed: \(self.hasAccessibility, privacy: .public)")
        }
        hotKeys?.onAction = { [weak self] action in
            switch action {
            case .copy(let index): self?.copy(to: index)
            case .paste(let index): self?.paste(from: index)
            }
        }
        shortcutError = hotKeys?.apply(settings)
        if registerHotKeys {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                self?.refreshAccessibility()
            }
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refreshAccessibility() }
        }
    }

    func applySettings(_ proposed: AppSettings) -> String? {
        guard !isBusy else { return "Wait for the current copy or paste to finish." }
        if let error = proposed.validationError { return error }
        if !store.canResize(to: proposed.slotCount) {
            return "Paste or discard the items in slots above \(proposed.slotCount) before reducing the limit."
        }
        if let error = hotKeys?.apply(proposed) { return error }
        settings = proposed
        store.resize(to: proposed.slotCount)
        if let lastPaste, lastPaste.index >= proposed.slotCount { self.lastPaste = nil }
        persistSettings(settings)
        shortcutError = nil
        settingsChanged?()
        return nil
    }

    func requestAccessibility() {
        refreshAccessibility()
        guard !hasAccessibility else { return }
        permissionWasRequested = true
        permissionRequest()
        if !permissionCheck() { showPermissionSettings() }
        refreshAccessibility()
    }

    func repairAccessibility() {
        guard !isBusy, !isRepairingPermission else { return }
        isRepairingPermission = true
        permissionRepair { [weak self] error in
            guard let self else { return }
            self.isRepairingPermission = false
            if let error { self.report(error, error: true); return }
            self.report("Permission record repaired. Enable Clipline in System Settings.")
            self.requestAccessibility()
        }
    }

    func refreshAccessibility() {
        let granted = permissionCheck()
        if hasAccessibility != granted {
            hasAccessibility = granted
            permissionLog.notice("Clipline event posting allowed: \(granted, privacy: .public)")
        }
        if granted {
            permissionWasRequested = false
            if messageIsPermissionError { report("Accessibility enabled · ready to copy and paste") }
        }
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func copy(to index: Int) {
        guard (0..<store.capacity).contains(index) else { return }
        if enqueueIfBusy(.copy(index)) { return }
        guard beginOperation() else { return }
        guard let target = targetApplication() else { finish(); return }
        showPanel?()
        waitForModifierRelease { [weak self] released in
            guard let self else { return }
            guard released, self.isFrontmost(target) else {
                self.report("Keep the source app focused and release the shortcut keys.", error: true)
                self.finish()
                return
            }
            let pasteboard = NSPasteboard.general
            let previousChange = pasteboard.changeCount
            guard self.sendKey(CGKeyCode(kVK_ANSI_C), to: target.processIdentifier) else {
                self.report("Couldn’t send Copy. Your slot is unchanged.", error: true)
                self.finish()
                return
            }
            self.waitForCopy(previousChange: previousChange, attempts: 30) { payload in
                if let payload {
                    self.store.save(payload, at: index)
                    self.report("Saved to slot \(index + 1)")
                } else {
                    self.report("Nothing copied. Select something and try again.", error: true)
                }
                self.finish()
            }
        }
    }

    func paste(from index: Int) {
        guard (0..<store.capacity).contains(index) else { return }
        if enqueueIfBusy(.paste(index)) { return }
        guard let payload = store.payload(at: index) else {
            report("Slot \(index + 1) is ready for something new.")
            return
        }
        guard beginOperation() else { return }
        guard let target = targetApplication() else { finish(); return }
        waitForModifierRelease { [weak self] released in
            guard let self else { return }
            guard released, self.isFrontmost(target) else {
                self.report("Keep the destination app focused and release the shortcut keys.", error: true)
                self.finish()
                return
            }
            guard payload.write(to: .general) else {
                self.report("Couldn’t prepare the clipboard. Your slot is still here.", error: true)
                self.finish()
                return
            }
            guard self.sendKey(CGKeyCode(kVK_ANSI_V), to: target.processIdentifier) else {
                self.report("Couldn’t send Paste. Your slot is still here.", error: true)
                self.finish()
                return
            }
            // Keep the pasteboard available: destination apps can read it asynchronously.
            // macOS has no cross-app acknowledgement that a paste was accepted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.store.clear(index)
                self.lastPaste = (index, payload)
                self.report("Pasted slot \(index + 1) · ready to reuse")
                self.finish()
            }
        }
    }

    private func beginOperation() -> Bool {
        guard !isBusy else { return false }
        refreshAccessibility()
        guard hasAccessibility else {
            showPanel?()
            report("Enable Accessibility to copy and paste between apps.", error: true)
            messageIsPermissionError = true
            return false
        }
        isBusy = true
        return true
    }

    private func targetApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            report("Choose the app you want to copy from or paste into.", error: true)
            return nil
        }
        return app
    }

    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private func sendKey(_ key: CGKeyCode, to process: pid_t) -> Bool {
        refreshAccessibility()
        guard hasAccessibility,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(process)
        up.postToPid(process)
        return true
    }

    private func waitForModifierRelease(attempts: Int = 80, completion: @escaping (Bool) -> Void) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if flags.intersection(modifiers).isEmpty { completion(true); return }
        guard attempts > 0 else { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForModifierRelease(attempts: attempts - 1, completion: completion)
        }
    }

    private func waitForCopy(previousChange: Int, attempts: Int, completion: @escaping (ClipboardPayload?) -> Void) {
        if NSPasteboard.general.changeCount != previousChange {
            completion(ClipboardPayload(pasteboard: .general))
            return
        }
        guard attempts > 0 else { completion(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.waitForCopy(previousChange: previousChange, attempts: attempts - 1, completion: completion)
        }
    }

    private func enqueueIfBusy(_ action: SlotAction) -> Bool {
        guard isBusy else { return false }
        guard pendingActions.count < 20, let target = targetApplication() else {
            report("Let the current shortcuts finish, then try again.", error: true)
            return true
        }
        pendingActions.append((action, target.processIdentifier))
        return true
    }

    private func finish() {
        isBusy = false
        runNextAction()
    }

    private func runNextAction() {
        guard !isBusy, !pendingActions.isEmpty else { return }
        let next = pendingActions.removeFirst()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == next.process else {
            report("App changed. Queued shortcuts were skipped; saved slots are safe.", error: true)
            pendingActions.removeAll()
            return
        }
        switch next.action {
        case .copy(let index): copy(to: index)
        case .paste(let index): paste(from: index)
        }
        // Empty slots and denied permissions finish without starting an operation.
        if !isBusy { runNextAction() }
    }

    func report(_ text: String, error: Bool = false) {
        message = text
        isError = error
        messageIsPermissionError = false
        let id = UUID()
        messageID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.messageID == id else { return }
            self.message = "Copy a little. Keep your flow."
            self.isError = false
        }
    }

    deinit {
        permissionTimer?.invalidate()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }
}
