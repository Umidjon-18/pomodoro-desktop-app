import Foundation
import SwiftData

/// An app that stays usable during every focus session.
@Model
final class AllowedApp {
    @Attribute(.unique) var bundleID: String
    var name: String
    var path: String

    init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}
