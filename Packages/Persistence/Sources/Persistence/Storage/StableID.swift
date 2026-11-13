import CryptoKit
import Foundation

/// Deterministic row IDs (name-based UUID version 5, RFC 9562).
///
/// CloudKit sync (SQLiteData) doesn't allow UNIQUE constraints other than the primary key,
/// because two devices could create the "same" row independently. Rows that must be unique
/// (one check-off per habit and day, one note per day, one report per week) instead get an ID
/// derived from what makes them unique. Two devices then create the same record, and sync
/// merges it instead of duplicating it.
enum StableID {
    /// The 66 Days namespace. Never change it: stored IDs depend on it.
    static let namespace = UUID(uuidString: "4C8E5D2A-66DA-4A5E-9B1F-6E3D2C1B0A99")!

    static func make(_ parts: String...) -> UUID { make(parts) }

    static func make(_ parts: [String]) -> UUID {
        var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
        data.append(contentsOf: Array(parts.joined(separator: "/").utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }
}
