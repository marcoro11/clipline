import Foundation
import Darwin

/// Hold a per-user lock for the lifetime of the GUI, including launches from
/// Terminal. Keeping the file avoids an unlink/recreate race during shutdown.
final class SingleInstanceLock {
    private let descriptor: Int32

    init?(url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("app.clipline.mac.lock")) {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); return nil }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}
