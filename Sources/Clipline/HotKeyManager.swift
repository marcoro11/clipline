import AppKit
import Carbon.HIToolbox

enum SlotAction: Equatable {
    case copy(Int)
    case paste(Int)

    init?(hotKeyID: UInt32, slotCount: Int) {
        let id = Int(hotKeyID)
        let index = id % SlotStore.maxCapacity
        guard id < SlotStore.maxCapacity * 2, index < slotCount else { return nil }
        self = id < SlotStore.maxCapacity ? .copy(index) : .paste(index)
    }
}

final class HotKeyManager {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x434C4950 // CLIP
    private var activeSettings: AppSettings?
    var onAction: ((SlotAction) -> Void)?

    init() {
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            var keyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                nil, &keyID)
            guard result == noErr, keyID.signature == manager.signature else {
                return OSStatus(eventNotHandledErr)
            }
            guard let action = SlotAction(hotKeyID: keyID.id,
                                          slotCount: manager.activeSettings?.slotCount ?? 0) else {
                return OSStatus(eventNotHandledErr)
            }
            manager.onAction?(action)
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// If any shortcut conflicts, restore the entire previous set.
    func apply(_ settings: AppSettings) -> String? {
        if let error = settings.validationError { return error }
        if let activeSettings,
           activeSettings.copyModifiers == settings.copyModifiers,
           activeSettings.pasteModifiers == settings.pasteModifiers,
           activeSettings.slotCount == settings.slotCount { return nil }
        let previous = activeSettings
        unregister()
        if let error = register(settings) {
            unregister()
            if let previous {
                if register(previous) != nil {
                    unregister()
                    activeSettings = nil
                    return error + " Previous shortcuts could not be restored. Try a different combination."
                }
            }
            activeSettings = previous
            return error
        }
        activeSettings = settings
        return nil
    }

    private func register(_ settings: AppSettings) -> String? {
        for (offset, modifiers) in [(0, settings.copyModifiers), (SlotStore.maxCapacity, settings.pasteModifiers)] {
            for (index, keyCode) in SlotKey.keyCodes.prefix(settings.slotCount).enumerated() {
                var reference: EventHotKeyRef?
                let id = EventHotKeyID(signature: signature, id: UInt32(offset + index))
                let status = RegisterEventHotKey(UInt32(keyCode), modifiers.carbonFlags, id,
                    GetApplicationEventTarget(), 0, &reference)
                guard status == noErr, let reference else {
                    let action = offset == 0 ? "Copy" : "Paste"
                    return "\(action) shortcut \(modifiers.symbols)\(SlotKey.label(for: index)) is unavailable (\(status)). Choose another combination."
                }
                references.append(reference)
            }
        }
        return nil
    }

    private func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
