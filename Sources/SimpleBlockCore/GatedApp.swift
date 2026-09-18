import Foundation

/// A gated desktop app, identified by bundle ID.
public struct GatedApp: Codable, Hashable, Identifiable {
    public var bundleId: String
    public var name: String
    /// The app's bundle path, e.g. "/Applications/Signal.app".
    public var path: String
    public var id: String { bundleId }

    public init(bundleId: String, name: String, path: String) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
    }
}

extension Array where Element == GatedApp {
    /// Renames an entry. An empty name keeps the old one.
    public mutating func rename(id: String, to name: String) {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].name = typed
    }
}
