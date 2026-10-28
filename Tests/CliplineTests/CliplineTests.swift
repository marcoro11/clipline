import AppKit
import Carbon.HIToolbox
import Testing
@testable import Clipline

private func textPayload(_ text: String) throws -> ClipboardPayload {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString(text, forType: .string)
    return try #require(ClipboardPayload(pasteboard: board))
}

@Suite("Configurable independent clipboard slots")
struct SlotTests {
    @Test func startsWithExactlyFiveEmptySlots() {
        let store = SlotStore()
        #expect(store.slots.map(\.id) == [0, 1, 2, 3, 4])
        #expect(store.occupiedCount == 0)
    }

    @Test func freeingOneSlotDoesNotMoveTheOthers() throws {
        let store = SlotStore()
        store.save(try textPayload("First"), at: 0)
        store.save(try textPayload("Third"), at: 2)
        store.save(try textPayload("Fifth"), at: 4)
        store.clear(2)
        #expect(store.occupiedCount == 2)
        #expect(store.payload(at: 0)?.preview == "First")
        #expect(store.payload(at: 2) == nil)
        #expect(store.payload(at: 4)?.preview == "Fifth")
        store.save(try textPayload("Reused"), at: 2)
        #expect(store.payload(at: 2)?.preview == "Reused")
        #expect(store.occupiedCount == 3)
    }

    @Test func copyingAgainReplacesOnlyThatSlot() throws {
        let store = SlotStore()
        store.save(try textPayload("Original"), at: 1)
        store.save(try textPayload("Unchanged"), at: 3)
        store.save(try textPayload("Replacement"), at: 1)
        #expect(store.occupiedCount == 2)
        #expect(store.payload(at: 1)?.preview == "Replacement")
        #expect(store.payload(at: 3)?.preview == "Unchanged")
    }

    @Test func invalidSlotNumbersAreIgnored() throws {
        let store = SlotStore()
        let payload = try textPayload("Text")
        store.save(payload, at: -1)
        store.save(payload, at: 5)
        store.clear(100)
        #expect(store.occupiedCount == 0)
        #expect(store.payload(at: -1) == nil)
        #expect(store.payload(at: 5) == nil)
    }

    @Test func clearAllReleasesEverySlot() throws {
        let store = SlotStore()
        for index in 0..<5 { store.save(try textPayload("Item \(index)"), at: index) }
        #expect(store.occupiedCount == 5)
        store.clearAll()
        #expect(store.slots.count == 5)
        #expect(store.occupiedCount == 0)
    }

    @Test func growsToTenWithoutMovingSavedItems() throws {
        let store = SlotStore()
        store.save(try textPayload("First"), at: 0)
        #expect(store.resize(to: 10))
        store.save(try textPayload("Tenth"), at: 9)
        #expect(store.capacity == 10)
        #expect(store.slots.map(\.id) == Array(0..<10))
        #expect(store.payload(at: 0)?.preview == "First")
        #expect(store.payload(at: 9)?.preview == "Tenth")
        store.clear(9)
        #expect(store.capacity == 10)
        #expect(store.occupiedCount == 1)
        store.clearAll()
        #expect(store.capacity == 10)
        #expect(store.occupiedCount == 0)
    }

    @Test func shrinkingNeverDiscardsOccupiedSlots() throws {
        let store = SlotStore(capacity: 10)
        store.save(try textPayload("Keep tenth"), at: 9)
        #expect(!store.resize(to: 5))
        #expect(store.capacity == 10)
        #expect(store.payload(at: 9)?.preview == "Keep tenth")
        store.clear(9)
        #expect(store.resize(to: 3))
        #expect(store.capacity == 3)
        #expect(!store.resize(to: 0))
        #expect(!store.resize(to: 11))
    }
}

@Suite("Clipboard data survives its source")
struct ClipboardTests {
    @Test func roundTripsRichTextAndMultipleItems() throws {
        let source = NSPasteboard.withUniqueName()
        let destination = NSPasteboard.withUniqueName()
        defer { destination.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("A formatted note", forType: .string)
        first.setData(Data("<b>A formatted note</b>".utf8), forType: .html)
        let second = NSPasteboardItem()
        second.setString("Another item", forType: .string)
        #expect(source.writeObjects([first, second]))
        let payload = try #require(ClipboardPayload(pasteboard: source))
        source.clearContents()
        source.releaseGlobally()
        #expect(payload.write(to: destination))
        #expect(destination.pasteboardItems?.count == 2)
        #expect(destination.pasteboardItems?[0].string(forType: .string) == "A formatted note")
        #expect(destination.pasteboardItems?[0].data(forType: .html) == Data("<b>A formatted note</b>".utf8))
        #expect(destination.pasteboardItems?[1].string(forType: .string) == "Another item")
    }

    @Test func emptyClipboardIsNotASavedItem() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        #expect(ClipboardPayload(pasteboard: board) == nil)
    }

    @Test func preservesUnicodeAndLineBreaks() throws {
        let payload = try textPayload("Caffè ☕️\r\nこんにちは\nSecond line")
        #expect(payload.preview == "Caffè ☕️\nこんにちは\nSecond line")
        let destination = NSPasteboard.withUniqueName()
        defer { destination.releaseGlobally() }
        #expect(payload.write(to: destination))
        #expect(destination.string(forType: .string) == "Caffè ☕️\r\nこんにちは\nSecond line")
    }

    @Test func preservesFileReferences() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = URL(fileURLWithPath: "/tmp/Clipline example.txt")
        #expect(board.writeObjects([url as NSURL]))
        let payload = try #require(ClipboardPayload(pasteboard: board))
        #expect(payload.kind == "File")
        #expect(payload.preview == "Clipline example.txt")
        let destination = NSPasteboard.withUniqueName()
        defer { destination.releaseGlobally() }
        #expect(payload.write(to: destination))
        #expect(destination.string(forType: .fileURL) == url.absoluteString)
    }
}

@Suite("Shortcut preferences")
struct SettingsTests {
    @Test func defaultsAreValidAndDistinct() {
        let settings = AppSettings()
        #expect(settings.validationError == nil)
        #expect(settings.copyModifiers.symbols == "⌥⌘")
        #expect(settings.pasteModifiers.symbols == "⌃⌘")
        #expect(settings.copyModifiers.carbonFlags == UInt32(optionKey | cmdKey))
    }

    @Test func preventsAmbiguousOrTypingOnlyShortcuts() {
        var settings = AppSettings()
        settings.pasteModifiers = settings.copyModifiers
        #expect(settings.validationError != nil)
        settings = AppSettings()
        settings.copyModifiers = []
        #expect(settings.validationError != nil)
        settings.copyModifiers = [.shift]
        #expect(settings.validationError != nil)
        settings.copyModifiers = ShortcutModifiers(rawValue: 1 << 10)
        #expect(settings.validationError != nil)
    }

    @Test func preferencesPersistAndCorruptPreferencesFallBack() throws {
        let suite = "app.clipline.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings()
        settings.copyModifiers = [.control, .option]
        settings.opacity = 0.7
        settings.theme = .dark
        settings.slotCount = 10
        settings.save(to: defaults)
        #expect(AppSettings.load(from: defaults) == settings)
        defaults.set(Data("not json".utf8), forKey: "clipline.settings")
        #expect(AppSettings.load(from: defaults) == AppSettings())
        settings.pasteModifiers = settings.copyModifiers
        settings.save(to: defaults)
        #expect(AppSettings.load(from: defaults) == AppSettings())
    }

    @Test func rejectsOutOfRangeOpacity() {
        var settings = AppSettings()
        settings.opacity = 0.1
        #expect(settings.validationError != nil)
        settings.opacity = 1.2
        #expect(settings.validationError != nil)
    }

    @Test func upgradesExistingPreferencesWithoutResettingShortcuts() throws {
        let legacy = Data(#"{"copyModifiers":3,"pasteModifiers":9,"opacity":0.7}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        #expect(settings.copyModifiers == [.control, .option])
        #expect(settings.pasteModifiers == [.control, .command])
        #expect(settings.opacity == 0.7)
        #expect(settings.slotCount == 5)
        #expect(settings.theme == .system)
    }

    @Test func slotLimitsAreValidated() {
        var settings = AppSettings()
        for count in [0, 11] {
            settings.slotCount = count
            #expect(settings.validationError != nil)
        }
        for count in [1, 5, 10] {
            settings.slotCount = count
            #expect(settings.validationError == nil)
        }
    }

    @Test func slotTenUsesZeroWithIndependentCopyAndPasteIDs() {
        #expect(SlotKey.label(for: 9) == "0")
        #expect(SlotKey.keyCodes[9] == kVK_ANSI_0)
        #expect(SlotKey.rangeLabel(for: 10) == "1–9, 0")
        #expect(SlotAction(hotKeyID: 9, slotCount: 10) == .copy(9))
        #expect(SlotAction(hotKeyID: 19, slotCount: 10) == .paste(9))
        #expect(SlotAction(hotKeyID: 9, slotCount: 5) == nil)
        #expect(SlotAction(hotKeyID: 19, slotCount: 5) == nil)
        #expect(SlotAction(hotKeyID: 20, slotCount: 10) == nil)
    }

    @Test func changingCapacityPreservesSavedDataAndPersistsNewSettings() throws {
        var saved: AppSettings?
        let controller = ClipboardController(settings: AppSettings(), registerHotKeys: false,
                                             persistSettings: { saved = $0 })
        controller.store.save(try textPayload("Existing"), at: 0)
        var proposed = controller.settings
        proposed.slotCount = 10
        proposed.theme = .dark
        #expect(controller.applySettings(proposed) == nil)
        #expect(saved == proposed)
        #expect(controller.store.capacity == 10)
        #expect(controller.store.payload(at: 0)?.preview == "Existing")
        controller.store.save(try textPayload("Tenth"), at: 9)
        proposed.slotCount = 5
        #expect(controller.applySettings(proposed) != nil)
        #expect(controller.settings.slotCount == 10)
        #expect(controller.store.payload(at: 9)?.preview == "Tenth")
        #expect(saved?.slotCount == 10)
    }
}

@Suite("Permission failures preserve saved items")
struct PermissionTests {
    @Test func eventPostingPermissionIsTheCopyPasteGate() {
        let eventsAllowed = PermissionStatus(accessibilityTrusted: false, eventPostingAllowed: true)
        #expect(eventsAllowed.canCopyAndPaste)
        let eventsDenied = PermissionStatus(accessibilityTrusted: true, eventPostingAllowed: false)
        #expect(!eventsDenied.canCopyAndPaste)
    }

    @Test func deniedPasteNeverConsumesTheSlot() throws {
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { false })
        controller.store.save(try textPayload("Keep me"), at: 2)
        controller.paste(from: 2)
        #expect(controller.store.payload(at: 2)?.preview == "Keep me")
        #expect(controller.isError)
        #expect(!controller.isBusy)
        #expect(!controller.canUndoPaste)
    }

    @Test func deniedCopyNeverReplacesAnExistingItem() throws {
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { false })
        controller.store.save(try textPayload("Original"), at: 4)
        controller.copy(to: 4)
        #expect(controller.store.payload(at: 4)?.preview == "Original")
        #expect(controller.isError)
        #expect(!controller.isBusy)
    }

    @Test func grantingPermissionClearsTheWarningWithoutLosingSlots() throws {
        var permission = false
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { permission })
        controller.store.save(try textPayload("Keep me"), at: 0)
        controller.paste(from: 0)
        #expect(controller.isError)
        #expect(!controller.hasAccessibility)
        permission = true
        controller.refreshAccessibility()
        #expect(controller.hasAccessibility)
        #expect(!controller.isError)
        #expect(controller.message == "Accessibility enabled · ready to copy and paste")
        #expect(controller.store.payload(at: 0)?.preview == "Keep me")
        permission = false
        controller.refreshAccessibility()
        #expect(!controller.hasAccessibility)
    }

    @Test func permissionRefreshDoesNotEraseUnrelatedErrors() {
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { true })
        controller.report("Unrelated clipboard error", error: true)
        controller.refreshAccessibility()
        #expect(controller.isError)
        #expect(controller.message == "Unrelated clipboard error")
    }

    @Test func repairPreservesSlotsAndRequestsOnlyTheNeededPermission() throws {
        var requests = 0
        var settingsOpened = 0
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { false },
            permissionRequest: { requests += 1 }, showPermissionSettings: { settingsOpened += 1 },
            permissionRepair: { completion in completion(nil) })
        controller.store.save(try textPayload("Keep through repair"), at: 0)
        controller.repairAccessibility()
        #expect(controller.store.payload(at: 0)?.preview == "Keep through repair")
        #expect(requests == 1)
        #expect(settingsOpened == 1)
        #expect(controller.permissionWasRequested)
        #expect(!controller.isRepairingPermission)
    }

    @Test func repairFailureDoesNotPromptOrConsumeSavedItems() throws {
        var requests = 0
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { false },
            permissionRequest: { requests += 1 }, showPermissionSettings: { requests += 1 },
            permissionRepair: { completion in completion("Repair failed") })
        controller.store.save(try textPayload("Still safe"), at: 1)
        controller.repairAccessibility()
        #expect(controller.isError)
        #expect(controller.message == "Repair failed")
        #expect(controller.store.payload(at: 1)?.preview == "Still safe")
        #expect(requests == 0)
        #expect(!controller.isRepairingPermission)
    }

    @Test func repairCannotStartTwiceAtTheSameTime() {
        var attempts = 0
        var complete: ((String?) -> Void)?
        let controller = ClipboardController(registerHotKeys: false, permissionCheck: { false },
            permissionRequest: {}, showPermissionSettings: {},
            permissionRepair: { completion in attempts += 1; complete = completion })
        controller.repairAccessibility()
        controller.repairAccessibility()
        #expect(attempts == 1)
        #expect(controller.isRepairingPermission)
        complete?(nil)
        #expect(!controller.isRepairingPermission)
    }
}

@Suite("One running GUI instance")
struct InstanceTests {
    @Test func duplicateCannotOwnTheLockAndQuittingReleasesIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clipline-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: file) }
        var first = SingleInstanceLock(url: file)
        #expect(first != nil)
        #expect(SingleInstanceLock(url: file) == nil)
        first = nil
        let replacement = try #require(SingleInstanceLock(url: file))
        withExtendedLifetime(replacement) {}
    }

    @Test func separateLockFilesDoNotConflict() throws {
        let directory = FileManager.default.temporaryDirectory
        let firstFile = directory.appendingPathComponent("clipline-a-\(UUID().uuidString).lock")
        let secondFile = directory.appendingPathComponent("clipline-b-\(UUID().uuidString).lock")
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }
        let first = try #require(SingleInstanceLock(url: firstFile))
        let second = try #require(SingleInstanceLock(url: secondFile))
        withExtendedLifetime((first, second)) {}
    }
}
