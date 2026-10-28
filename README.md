# Clipline

A small macOS menu bar app with up to ten independent clipboard slots and a translucent, draggable sticky panel. It starts with five slots. Copy several things while you're in one app, then paste them individually in another.

## Run

Requires macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`). Tests require a Swift 6 toolchain. No third-party packages or network services are used.

```sh
./scripts/build.sh --run
```

The application is built at `build/Clipline.app`. Keep it at a stable location once you grant Accessibility. Local builds use a persistent self-signed development identity in the project-private `.local-signing/` folder, so the designated signing requirement stays the same across updates. Its private keychain is passed directly to `codesign`, then locked; it is not added to the login keychain, keychain search list, or system certificate trust. Keep this ignored folder private and retain it across builds. Deleting it creates a new identity and requires granting permissions again. Set `CLIPLINE_SIGNING_IDENTITY` to use an existing code-signing identity instead. Distribution to other computers requires Developer ID signing and notarization.

On first use, click **Enable copy & paste** and allow **Clipline** in **System Settings → Privacy & Security → Accessibility**. If macOS doesn't list the app, add `build/Clipline.app` with the **+** button. If permission doesn't take effect immediately, quit and reopen Clipline.

If a grant is stuck after updating an older build, use **Repair permission record** in the panel or settings. It runs `tccutil reset` for Clipline's **Accessibility** and **PostEvent** records, then asks macOS for event-posting access again. Saved slots are preserved, and other apps' permissions are untouched. Use **Show this copy in Finder** to locate the running app if needed. Paste saved items before any manual quit/reopen. The app rechecks permission when you return from System Settings, on application activation, periodically, and before every copy/paste. **Check again** refreshes it immediately and clears a stale permission warning once access is granted.

Permission checks and requests use `CGPreflightPostEventAccess` and `CGRequestPostEventAccess`, matching the keyboard-event operation used for Copy/Paste. General Accessibility-client trust is a separate diagnostic and does not gate keyboard events. To inspect both values without launching another GUI or asking for access:

```sh
build/Clipline.app/Contents/MacOS/Clipline --diagnose-permissions
```

macOS may attribute a Terminal child process's permission checks to Terminal. To check Clipline as a Launch Services application, without opening a second panel or registering shortcuts, run:

```sh
open -n -g -W build/Clipline.app --args --diagnose-permissions /tmp/clipline-permissions.json
cat /tmp/clipline-permissions.json
```

The running GUI also logs permission transitions with subsystem `app.clipline.mac` and category `permissions`. No clipboard content is logged.

The GUI is restricted to the bundled app, with a per-user single-instance lock to prevent duplicate processes competing for shortcuts. `--help` exits immediately rather than opening the GUI.

## Use

| Action | Default shortcut |
| --- | --- |
| Copy selection into slot 1–5 | **⌥⌘1** through **⌥⌘5** |
| Paste slot 1–5, then free it | **⌃⌘1** through **⌃⌘5** |
| Paste with the mouse | Click a filled slot while the destination app is focused |
| Discard one item | Click the **×** on its row |
| Hide / show the panel | Click the menu bar icon |
| Settings / clear all / quit | Right-click the menu bar icon |

In **Settings**, select the modifier keys for each of the two shortcut families. Add a number from 1 to 5 when using them. Copy and paste must use different combinations. Unavailable shortcuts are reported; the previous set is restored if a change fails. Panel opacity is adjustable from 55% to 100%.

Choose **System**, **Light**, or **Dark** appearance in Settings. The panel and settings both use the chosen theme. Set **Clipboard slots** to any limit from **1 to 10**, with **5** as the default. For slots 6–9, use their number keys; **slot 10 uses 0**. Only shortcuts for configured slots are registered. The slot list scrolls once there are more than five. Reducing the limit is blocked while removed slots still contain items, so saved content is preserved. Existing shortcut preferences survive the upgrade.

The panel floats over other apps and across Spaces without taking keyboard focus. Drag its title area to move it; an open-hand cursor marks the draggable area, and its position is remembered. Copying into an occupied slot replaces that slot. Freeing a slot does not renumber the others.

## Data and paste behavior

- Slots are held in memory and clear when the app quits. Only settings and panel position are saved.
- The app reads the clipboard only when you ask it to copy, rather than collecting a background clipboard history.
- Text, rich text, images, file references, and other available pasteboard representations are retained. File references point to the original files; moving or deleting the files can invalidate them.
- A paste sends the standard Paste command to the focused app and frees the slot shortly afterwards. macOS does not acknowledge whether another app accepted the paste. **Restore slot** recovers the last consumed item if needed; it does not undo changes in the destination app.
- Pasted content remains on the system clipboard so apps have time to read it, and ordinary **⌘V** can paste it again. Clearing slots does not clear the system clipboard.
- Apps that block standard Copy/Paste, secure fields, or custom copy workflows may not work. Without Accessibility permission, slots are never consumed by a failed paste attempt.

## Development

```sh
./scripts/test.sh
```

The test suite uses private pasteboards and isolated preference domains, leaving the normal system clipboard untouched. It verifies stable slot numbers and reuse, rich content and file-reference round trips, shortcut validation, and settings persistence. Cross-app keyboard automation needs a manual check after granting Accessibility.

The app uses SwiftUI for the panel and settings, AppKit for a nonactivating `NSPanel` and pasteboards, Carbon for global shortcut registration, and Core Graphics to send Copy/Paste to the destination process.

To export sample-data previews of the actual SwiftUI views without capturing your screen or changing the system clipboard:

```sh
build/Clipline.app/Contents/MacOS/Clipline --render-previews build/previews
```
