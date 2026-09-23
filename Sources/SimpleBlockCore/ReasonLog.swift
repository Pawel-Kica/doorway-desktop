import Foundation

public enum LogKind: String, Codable {
    /// `locked`: a super-locked app tried to open and was quit.
    /// `hidden`: an app outside a focus session tried to come forward and was hidden.
    /// `focus`: a focus session ended; `reason` lists its allowed apps, `minutes` how long it ran.
    case launch, `switch`, expired, cancelled, locked, quit, hidden, focus

    /// Kinds that carry a typed reason.
    public var hasReason: Bool { self == .launch || self == .switch || self == .expired }
}

/// One line of reasons.jsonl.
public struct LogEntry: Codable, Equatable {
    public var ts: Date
    public var bundleId: String
    public var app: String
    public var kind: LogKind
    public var reason: String?
    /// Only on `focus`: minutes the session ran.
    public var minutes: Int?

    public init(ts: Date, bundleId: String, app: String, kind: LogKind, reason: String? = nil, minutes: Int? = nil) {
        self.ts = ts
        self.bundleId = bundleId
        self.app = app
        self.kind = kind
        self.reason = reason
        self.minutes = minutes
    }
}

/// JSON line encoding. `ts` is ISO 8601 with the local offset, `reason` and `minutes` are omitted when nil.
public enum LogCodec {
    public static func encode(_ entry: LogEntry, timeZone: TimeZone = .current) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return String(decoding: try encoder.encode(entry), as: UTF8.self)
    }

    public static func decode(_ line: String) throws -> LogEntry {
        let formatter = ISO8601DateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(text)")
            }
            return date
        }
        return try decoder.decode(LogEntry.self, from: Data(line.utf8))
    }
}

/// Append-only JSONL file of log entries. Unreadable lines are skipped on read.
public struct ReasonLog {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// ~/Library/Application Support/SimpleBlock/reasons.jsonl
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SimpleBlock/reasons.jsonl")
    }

    public func append(_ entry: LogEntry) throws {
        let line = Data((try LogCodec.encode(entry) + "\n").utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: url) else { return try line.write(to: url) }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func readAll() -> [LogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? LogCodec.decode(String($0)) }
    }
}

/// Reasons given today (launch/switch/expired), for one app or all of them.
public func reasonsToday(_ entries: [LogEntry], bundleId: String? = nil, now: Date, calendar: Calendar = .current) -> Int {
    entries.filter {
        $0.kind.hasReason && (bundleId == nil || $0.bundleId == bundleId) && calendar.isDate($0.ts, inSameDayAs: now)
    }.count
}
