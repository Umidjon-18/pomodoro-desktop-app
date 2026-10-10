import Foundation
import SwiftData

/// A domain that is unreachable while a focus session runs (when enabled).
@Model
final class BlockedDomain {
    /// Normalized, lowercase host such as "youtube.com" (see `HostsBlock.normalize`).
    @Attribute(.unique) var domain: String
    var isEnabled: Bool
    var createdAt: Date

    init(domain: String, isEnabled: Bool = true, createdAt: Date = .now) {
        self.domain = domain
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
