import AppKit

@main
enum CliplineApplication {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst() == ["--help"] {
            print("Clipline: open the bundled Clipline.app. Options: --diagnose-permissions, --render-previews <directory>.")
            return
        }
        if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--diagnose-permissions" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(AccessibilityPermission.status()) {
                if CommandLine.arguments.count == 3 {
                    let url = URL(fileURLWithPath: CommandLine.arguments[2])
                    do {
                        try data.write(to: url, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    } catch {
                        fputs("Couldn’t write diagnostics: \(error.localizedDescription)\n", stderr)
                    }
                } else if let text = String(data: data, encoding: .utf8) { print(text) }
            }
            return
        }
        let application = NSApplication.shared
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-previews" {
            do {
                try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
            } catch {
                fputs("Preview failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            fputs("Run ./scripts/build.sh --run to launch the bundled Clipline.app.\n", stderr)
            return
        }
        guard let instance = SingleInstanceLock() else {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("app.clipline.mac.show-panel"), object: nil, deliverImmediately: true)
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime((delegate, instance)) { application.run() }
    }
}
