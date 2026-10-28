import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark

    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum SlotKey {
    static let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                           kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]

    static func label(for index: Int) -> String { index == 9 ? "0" : String(index + 1) }

    static func rangeLabel(for count: Int) -> String {
        count == 10 ? "1–9, 0" : (count == 1 ? "1" : "1–\(count)")
    }
}

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt32

    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)
    static let copyDefault: Self = [.option, .command]
    static let pasteDefault: Self = [.control, .command]

    var isValid: Bool {
        !intersection([.control, .option, .command]).isEmpty
            && subtracting([.control, .option, .shift, .command]).isEmpty
    }

    var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

struct AppSettings: Codable, Equatable {
    var copyModifiers: ShortcutModifiers = .copyDefault
    var pasteModifiers: ShortcutModifiers = .pasteDefault
    var opacity: Double = 0.95
    var theme: AppTheme = .system
    var slotCount: Int = SlotStore.defaultCapacity

    init() {}

    private enum CodingKeys: String, CodingKey {
        case copyModifiers, pasteModifiers, opacity, theme, slotCount
    }

    // Preserve existing shortcuts and opacity when upgrading older preferences.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        copyModifiers = try values.decodeIfPresent(ShortcutModifiers.self, forKey: .copyModifiers) ?? .copyDefault
        pasteModifiers = try values.decodeIfPresent(ShortcutModifiers.self, forKey: .pasteModifiers) ?? .pasteDefault
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.95
        theme = try values.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        slotCount = try values.decodeIfPresent(Int.self, forKey: .slotCount) ?? SlotStore.defaultCapacity
    }

    var validationError: String? {
        if !copyModifiers.isValid || !pasteModifiers.isValid {
            return "Include Control, Option, or Command in each shortcut."
        }
        if copyModifiers == pasteModifiers {
            return "Choose different combinations for copy and paste."
        }
        if !(0.55...1).contains(opacity) {
            return "Choose an opacity between 55% and 100%."
        }
        if !(1...SlotStore.maxCapacity).contains(slotCount) {
            return "Choose between 1 and \(SlotStore.maxCapacity) slots."
        }
        return nil
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "clipline.settings"),
              let settings = try? JSONDecoder().decode(Self.self, from: data),
              settings.validationError == nil else { return Self() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "clipline.settings")
    }
}

/// Eagerly retain every available representation; a source app may exit later.
struct ClipboardPayload {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let preview: String
    let kind: String
    let symbol: String

    init?(pasteboard: NSPasteboard) {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        self.items = items

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            preview = urls.map(\.lastPathComponent).joined(separator: ", ")
            kind = urls.count == 1 ? "File" : "\(urls.count) files"
            symbol = "doc"
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            preview = text.replacingOccurrences(of: "\r\n", with: "\n")
            kind = "Text"
            symbol = "text.alignleft"
        } else if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            preview = "Copied image"
            kind = "Image"
            symbol = "photo"
        } else {
            preview = "Copied content"
            kind = "Clipboard item"
            symbol = "doc.on.clipboard"
        }
    }

    @discardableResult
    func write(to pasteboard: NSPasteboard) -> Bool {
        let objects = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}

struct ClipboardSlot: Identifiable {
    let id: Int
    var payload: ClipboardPayload?
}

final class SlotStore: ObservableObject {
    static let defaultCapacity = 5
    static let maxCapacity = 10
    @Published private(set) var slots: [ClipboardSlot]

    init(capacity: Int = defaultCapacity) {
        let count = min(max(capacity, 1), Self.maxCapacity)
        slots = (0..<count).map { ClipboardSlot(id: $0) }
    }

    var capacity: Int { slots.count }

    func canResize(to count: Int) -> Bool {
        (1...Self.maxCapacity).contains(count)
            && !slots.dropFirst(count).contains(where: { $0.payload != nil })
    }

    @discardableResult
    func resize(to count: Int) -> Bool {
        guard canResize(to: count) else { return false }
        if count < capacity { slots = Array(slots.prefix(count)) }
        else if count > capacity { slots += (capacity..<count).map { ClipboardSlot(id: $0) } }
        return true
    }

    var occupiedCount: Int { slots.filter { $0.payload != nil }.count }

    func payload(at index: Int) -> ClipboardPayload? {
        guard slots.indices.contains(index) else { return nil }
        return slots[index].payload
    }

    func save(_ payload: ClipboardPayload, at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index].payload = payload
    }

    func clear(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index].payload = nil
    }

    func clearAll() {
        slots = (0..<capacity).map { ClipboardSlot(id: $0) }
    }
}
