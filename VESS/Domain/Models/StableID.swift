import CryptoKit
import Foundation

nonisolated extension UUID {
    /// A UUID derived deterministically from `key` (SHA-256, formatted as an
    /// RFC 4122 v5-style UUID). The same key always gives the same ID, so a
    /// catalog food or a product's barcode maps to one stable identity.
    init(stableKey key: String) {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        self.init(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                         bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
