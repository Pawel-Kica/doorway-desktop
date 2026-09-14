import Foundation

/// A gated app, identified by bundle ID, or a gated site, gated through its Chrome web app.
public struct GatedApp: Codable, Hashable, Identifiable {
    /// For a site: its host, e.g. "mail.google.com".
    public var bundleId: String
    public var name: String
    /// For an app: its bundle path. For a site: the URL as added, e.g. "https://mail.google.com/mail/u/0/#inbox".
    public var path: String
    public var id: String { bundleId }
    public var isSite: Bool { path.contains("://") }

    public init(bundleId: String, name: String, path: String) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
    }
}

/// Info.plist key of a Chrome (or other Chromium) web app shim, e.g. "https://mail.google.com/mail/u/0/".
/// Each installed web app is its own .app with its own bundle ID, so a site is gated like any app.
public let webAppURLKey = "CrAppModeShortcutURL"

/// The host a site entry gates, from what was typed: "https://mail.google.com/mail/u/0/#inbox" or "mail.google.com".
/// Lowercased, "www." dropped.
public func siteHost(_ input: String) -> String? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let url = URL(string: text.contains("://") ? text : "https://" + text)
    guard let host = url?.host?.lowercased(), host.contains(".") || host == "localhost" else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

/// The gated site a web app with this start URL belongs to. A site covers its host and subdomains,
/// so a mail.google.com app matches "google.com" but a docs.google.com app doesn't match "mail.google.com".
/// The most specific site wins.
public func gatedSite(forWebAppURL url: String, in entries: [GatedApp]) -> GatedApp? {
    guard let host = siteHost(url) else { return nil }
    return entries
        .filter { $0.isSite && (host == $0.bundleId || host.hasSuffix("." + $0.bundleId)) }
        .max { $0.bundleId.count < $1.bundleId.count }
}

extension Array where Element == GatedApp {
    /// Adds a site from Settings. False when the URL has no usable host or the site is already there.
    public mutating func addSite(name: String, url: String) -> Bool {
        guard let host = siteHost(url), !contains(where: { $0.bundleId == host }) else { return false }
        append(GatedApp(bundleId: host, name: Self.name(name, or: host), path: Self.fullURL(url)))
        return true
    }

    /// Renames an entry and, for a site, changes its URL. An empty name keeps the old one.
    /// False when the entry is gone, the URL has no usable host, or another entry already has that host.
    public mutating func edit(id: String, name: String, url: String? = nil) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }) else { return false }
        var entry = self[index]
        entry.name = Self.name(name, or: entry.name)
        if entry.isSite, let url {
            guard let host = siteHost(url), !contains(where: { $0.bundleId == host && $0.id != id }) else { return false }
            entry.bundleId = host
            entry.path = Self.fullURL(url)
        }
        self[index] = entry
        return true
    }

    private static func name(_ typed: String, or fallback: String) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    private static func fullURL(_ typed: String) -> String {
        let url = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.contains("://") ? url : "https://" + url
    }
}
