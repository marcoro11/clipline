import ApplicationServices
import AppKit

struct PermissionStatus: Codable, Equatable {
    let accessibilityTrusted: Bool
    let eventPostingAllowed: Bool

    // Clipline synthesizes keyboard events; it does not inspect other apps via AX.
    var canCopyAndPaste: Bool { eventPostingAllowed }
}

enum AccessibilityPermission {
    static let bundleIdentifier = "app.clipline.mac"

    static func status() -> PermissionStatus {
        PermissionStatus(accessibilityTrusted: AXIsProcessTrusted(),
                         eventPostingAllowed: CGPreflightPostEventAccess())
    }

    static func isGranted() -> Bool { CGPreflightPostEventAccess() }

    static func request() {
        _ = CGRequestPostEventAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Use the supported reset utility, scoped to this app. Never edit TCC.db or
    /// request private entitlements mentioned in system diagnostic messages.
    static func repair(completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for service in ["Accessibility", "PostEvent"] {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    process.arguments = ["reset", service, bundleIdentifier]
                    let errors = Pipe()
                    process.standardError = errors
                    process.standardOutput = FileHandle.nullDevice
                    try process.run()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let error = "macOS could not reset Clipline’s \(service) permission. \(detail)"
                        DispatchQueue.main.async { completion(error) }
                        return
                    }
                }
                DispatchQueue.main.async { completion(nil) }
            } catch {
                let message = "Couldn’t start permission repair: \(error.localizedDescription)"
                DispatchQueue.main.async { completion(message) }
            }
        }
    }
}
