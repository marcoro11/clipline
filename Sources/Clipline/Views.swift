import AppKit
import SwiftUI

private enum Palette {
    private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let values = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }

    static let ink = adaptive((0.22, 0.23, 0.21), (0.93, 0.93, 0.90))
    static let muted = adaptive((0.48, 0.47, 0.43), (0.67, 0.68, 0.66))
    static let accent = adaptive((0.72, 0.36, 0.22), (0.96, 0.61, 0.41))
    static let paper = adaptive((0.99, 0.97, 0.91), (0.12, 0.13, 0.14))
    static let card = adaptive((1, 1, 1), (0.23, 0.24, 0.25))
    static let highlight = adaptive((1, 1, 1), (0.35, 0.36, 0.37))
}

struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SlotPanelView: View {
    @ObservedObject var controller: ClipboardController
    @ObservedObject var store: SlotStore
    let openSettings: () -> Void
    let hide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.slots) { slot in
                        SlotRow(slot: slot, settings: controller.settings, busy: controller.isBusy,
                            paste: { controller.paste(from: slot.id) },
                            clear: { store.clear(slot.id) })
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(height: min(CGFloat(store.capacity * 81 - 8), 397))

            if !controller.hasAccessibility {
                Button(action: controller.requestAccessibility) {
                    HStack(spacing: 9) {
                        Image(systemName: "hand.raised")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Enable copy & paste").font(.system(size: 12, weight: .semibold))
                            Text("Allow Accessibility in System Settings")
                                .font(.system(size: 10))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(12)
                    .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                if controller.permissionWasRequested {
                    HStack {
                        Text("Already enabled?")
                        Button("Check again", action: controller.refreshAccessibility)
                        Button("Show app", action: controller.revealApplication)
                    }
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                Button(controller.isRepairingPermission ? "Repairing…" : "Repair permission record") {
                    controller.repairAccessibility()
                }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.accent)
                .disabled(controller.isRepairingPermission || controller.isBusy)
                .help("Reset only Clipline’s stale permission record, then request access again. Saved slots are kept.")
                .padding(.top, 8)
            }

            if let error = controller.shortcutError {
                Button(action: openSettings) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: controller.isError ? "exclamationmark.circle" : "sparkle")
                    .padding(.top, 1)
                Text(controller.message).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(controller.isError ? Palette.accent : Palette.muted)
            .frame(minHeight: 30, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 14)

            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1).padding(.horizontal, 18)
            HStack(spacing: 5) {
                Circle().fill(store.occupiedCount > 0 ? Palette.accent : Palette.muted.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(store.occupiedCount == 0 ? "All \(store.capacity) slots are ready" : "\(store.occupiedCount) of \(store.capacity) waiting to paste")
                    .font(.system(size: 10.5))
                Spacer()
                if controller.canUndoPaste {
                    Button("Restore slot") { controller.undoPaste() }
                        .buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .help("Restore the last used slot. This does not undo typing in the destination app.")
                        .font(.system(size: 10.5))
                } else if store.occupiedCount > 0 {
                    Button("Clear all") { controller.clearAll() }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .font(.system(size: 10.5))
                        .disabled(controller.isBusy)
                }
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .background {
            FrostedGlass().overlay(Palette.paper.opacity(0.72))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Palette.highlight.opacity(0.7), lineWidth: 1)
        }
        .foregroundStyle(Palette.ink)
        .frame(width: 340)
        .preferredColorScheme(controller.settings.theme.colorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Text("clipline").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                Spacer()
                Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }
                    .help("Settings")
                    .accessibilityLabel("Open settings")
                Button(action: hide) { Image(systemName: "minus") }
                    .help("Hide panel · reopen from the menu bar")
                    .accessibilityLabel("Hide panel")
            }
            .buttonStyle(QuietIconButtonStyle())
            Text("A little room for your clipboard.")
                .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 23)
        .padding(.bottom, 21)
        .overlay {
            // Keep the settings and hide buttons outside the drag surface.
            WindowDragArea()
                .padding(.trailing, 86)
                .help("Drag to move Clipline")
                .accessibilityHidden(true)
        }
    }
}

private struct SlotRow: View {
    let slot: ClipboardSlot
    let settings: AppSettings
    let busy: Bool
    let paste: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: { if slot.payload != nil { paste() } }) {
                HStack(spacing: 12) {
                    Text("\(slot.id + 1)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(slot.payload == nil ? Palette.muted.opacity(0.6) : Palette.accent)
                        .frame(width: 30, height: 34)
                        .background(slot.payload == nil ? Palette.ink.opacity(0.035) : Palette.accent.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        if let payload = slot.payload {
                            Text(payload.preview)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 4) {
                                Image(systemName: payload.symbol).font(.system(size: 8))
                                Text(payload.kind.uppercased()).font(.system(size: 8, weight: .medium)).tracking(1)
                                Spacer()
                                Text("\(settings.pasteModifiers.symbols)\(SlotKey.label(for: slot.id))")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundStyle(Palette.muted)
                        } else {
                            Text("Slot ready").font(.system(size: 12)).foregroundStyle(Palette.muted.opacity(0.8))
                            Text("Copy with \(settings.copyModifiers.symbols)\(SlotKey.label(for: slot.id))")
                                .font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.65))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 12)
                .padding(.trailing, slot.payload == nil ? 12 : 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .allowsHitTesting(slot.payload != nil)
            .accessibilityLabel(slot.payload.map { "Paste slot \(slot.id + 1): \($0.preview)" } ?? "Slot \(slot.id + 1), empty")
            .help(slot.payload == nil ? "Copy a selection with \(settings.copyModifiers.symbols)\(SlotKey.label(for: slot.id))" : "Paste into your current app and free this slot")

            if slot.payload != nil {
                Button(action: clear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.muted.opacity(0.7))
                        .frame(width: 24, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .disabled(busy)
                .help("Discard slot \(slot.id + 1)")
                .accessibilityLabel("Discard slot \(slot.id + 1)")
            }
        }
        .frame(height: 73)
        .background(Palette.card.opacity(slot.payload == nil ? 0.15 : 0.55),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Palette.ink.opacity(slot.payload == nil ? 0.06 : 0.09),
                              style: StrokeStyle(lineWidth: 1, dash: slot.payload == nil ? [3, 4] : []))
        }
    }
}

private struct QuietIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .frame(width: 25, height: 27)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.1 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}

private final class SettingsDraft: ObservableObject {
    @Published var settings: AppSettings
    @Published var error: String?

    init(settings: AppSettings, error: String?) {
        self.settings = settings
        self.error = error
    }
}

struct SettingsView: View {
    @ObservedObject var controller: ClipboardController
    @StateObject private var state: SettingsDraft
    let close: () -> Void

    init(controller: ClipboardController, close: @escaping () -> Void) {
        self.controller = controller
        self.close = close
        _state = StateObject(wrappedValue: SettingsDraft(settings: controller.settings, error: controller.shortcutError))
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Make it your own.")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
                Text("Two combinations. A little space to keep things.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }

            HStack {
                Text("Appearance").font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("Appearance", selection: $state.settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in Text(theme.title).tag(theme) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 240)
            }

            VStack(alignment: .leading, spacing: 7) {
                Stepper(value: $state.settings.slotCount, in: 1...SlotStore.maxCapacity) {
                    HStack {
                        Text("Clipboard slots").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(state.settings.slotCount)").font(.system(size: 12, design: .monospaced))
                    }
                }
                Text("Up to 10 slots · default 5. Slot 10 uses the 0 key.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }

            VStack(spacing: 20) {
                shortcutEditor(title: "Copy into a slot", subtitle: "Saves your selection, replacing anything in that slot.",
                               modifiers: $state.settings.copyModifiers)
                Divider()
                shortcutEditor(title: "Paste from a slot", subtitle: "Pastes into your current app, then frees the slot.",
                               modifiers: $state.settings.pasteModifiers)
            }
            .padding(20)
            .background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Panel opacity").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(state.settings.opacity * 100))%")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                Slider(value: $state.settings.opacity, in: 0.55...1, step: 0.05).tint(Palette.accent)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: controller.hasAccessibility ? "checkmark.shield" : "hand.raised")
                    .foregroundStyle(Palette.accent).font(.system(size: 17))
                VStack(alignment: .leading, spacing: 5) {
                    Text(controller.hasAccessibility ? "Ready to copy and paste" : "Allow Accessibility to get started")
                        .font(.system(size: 12, weight: .medium))
                    Text("Clipline needs this permission to send Copy and Paste to other apps.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if !controller.hasAccessibility {
                        HStack(spacing: 12) {
                            Button("Open System Settings", action: controller.requestAccessibility)
                            Button("Check again", action: controller.refreshAccessibility)
                        }.font(.system(size: 11)).padding(.top, 3)
                        if controller.permissionWasRequested {
                            Text("Already enabled? Repair Clipline’s permission record below, then enable it when macOS asks. Saved slots are kept.")
                                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Show this copy in Finder", action: controller.revealApplication)
                                .font(.system(size: 11))
                        }
                        Button(controller.isRepairingPermission ? "Repairing…" : "Repair permission record") {
                            controller.repairAccessibility()
                        }
                        .font(.system(size: 11))
                        .disabled(controller.isRepairingPermission || controller.isBusy)
                    }
                }
            }

            if let error = state.error ?? state.settings.validationError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Reset defaults") { state.settings = AppSettings(); state.error = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save settings") {
                    if let failure = controller.applySettings(state.settings) { state.error = failure }
                    else { close() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.settings.validationError != nil || controller.isBusy)
            }

            Text("Slots stay in memory and clear when you quit. Standard ⌘C and ⌘V still work as usual.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        }
        .frame(width: 500, height: min(820, (NSScreen.main?.visibleFrame.height ?? 920) - 100))
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(state.settings.theme.colorScheme)
    }

    private func shortcutEditor(title: String, subtitle: String, modifiers: Binding<ShortcutModifiers>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(modifiers.wrappedValue.symbols.isEmpty ? "—" : modifiers.wrappedValue.symbols) \(SlotKey.rangeLabel(for: state.settings.slotCount))")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.accent)
            }
            Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            HStack(spacing: 7) {
                ForEach(Array([(ShortcutModifiers.control, "⌃ Control"), (.option, "⌥ Option"),
                               (.shift, "⇧ Shift"), (.command, "⌘ Command")].enumerated()), id: \.offset) { _, entry in
                    let selected = modifiers.wrappedValue.contains(entry.0)
                    Button {
                        if selected { modifiers.wrappedValue.remove(entry.0) }
                        else { modifiers.wrappedValue.insert(entry.0) }
                        state.error = nil
                    } label: {
                        Text(entry.1).font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .foregroundStyle(selected ? Palette.accent : Palette.muted)
                            .background(selected ? Palette.accent.opacity(0.12) : Palette.ink.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(selected ? Palette.accent.opacity(0.25) : .clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.1)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
            Text(state.settings.slotCount == 10
                 ? "Hold the selected keys and press 1–9, or 0 for slot 10."
                 : "Hold the selected keys and press a slot number (\(SlotKey.rangeLabel(for: state.settings.slotCount))).")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }
}
