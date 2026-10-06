import Foundation

/// An iPhone app Doorway can gate. The raw value is the stable ID used in storage and in doorway://gate/<id>.
/// The AppEnum conformance for Shortcuts lives in the app target (App/GatedApp+AppEnum.swift).
public enum GatedApp: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case signal, messages, whatsapp, telegram, messenger, instagram, x, slack, discord, mail, gmail, linkedin, youtube

    public var name: String {
        switch self {
        case .signal: "Signal"
        case .messages: "Messages"
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .messenger: "Messenger"
        case .instagram: "Instagram"
        case .x: "X"
        case .slack: "Slack"
        case .discord: "Discord"
        case .mail: "Mail"
        case .gmail: "Gmail"
        case .linkedin: "LinkedIn"
        case .youtube: "YouTube"
        }
    }

    /// URL scheme that opens the app.
    public var url: URL {
        switch self {
        case .signal: URL(string: "sgnl://")!
        case .messages: URL(string: "messages://")!
        case .whatsapp: URL(string: "whatsapp://")!
        case .telegram: URL(string: "tg://")!
        case .messenger: URL(string: "fb-messenger://")!
        case .instagram: URL(string: "instagram://")!
        case .x: URL(string: "twitter://")!
        case .slack: URL(string: "slack://")!
        case .discord: URL(string: "discord://")!
        case .mail: URL(string: "message://")!
        case .gmail: URL(string: "googlegmail://")!
        case .linkedin: URL(string: "linkedin://")!
        case .youtube: URL(string: "youtube://")!
        }
    }
}
