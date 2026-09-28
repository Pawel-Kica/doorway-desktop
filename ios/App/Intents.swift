import AppIntents

/// Lets Shortcuts pick a gated app. Literal display names, the metadata extractor can't read `name`. Public because
/// GatedApp is (Core is public for its test package).
extension GatedApp: AppEnum {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    public static let caseDisplayRepresentations: [GatedApp: DisplayRepresentation] = [
        .signal: "Signal",
        .messages: "Messages",
        .whatsapp: "WhatsApp",
        .telegram: "Telegram",
        .messenger: "Messenger",
        .instagram: "Instagram",
        .x: "X",
        .slack: "Slack",
        .discord: "Discord",
        .mail: "Mail",
        .gmail: "Gmail",
        .linkedin: "LinkedIn",
        .youtube: "YouTube",
    ]
}

/// The one action in a "<App> Is Opened, Run Immediately" automation. Returns silently while the app is unlocked,
/// otherwise brings Simple Block forward with the prompt.
struct GateAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Gate App"
    static let description = IntentDescription("Asks for a reason before the app opens. Lets it through for a few minutes after one.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "App")
    var app: GatedApp

    static var parameterSummary: some ParameterSummary {
        Summary("Gate \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = Model.shared
        if model.state.isUnlocked(app, now: .now) { return .result() }
        model.pending = app
        do {
            try await continueInForeground(alwaysConfirm: false)
        } catch {
            // Declined or not allowed: don't leave a stale prompt for the next time Simple Block opens.
            model.pending = nil
            throw error
        }
        return .result()
    }
}

/// Plan B, step 1: true when the app needs a reason. Runs in the background, never shows anything.
struct NeedsReasonIntent: AppIntent {
    static let title: LocalizedStringResource = "Needs Reason"
    static let description = IntentDescription("True when the app is not unlocked. Pair with If and Ask Reason.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App")
    var app: GatedApp

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$app) needs a reason")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: !Model.shared.state.isUnlocked(app, now: .now))
    }
}

/// Plan B, step 2: opens Simple Block with the prompt.
struct AskReasonIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Reason"
    static let description = IntentDescription("Opens Simple Block and asks for a reason.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "App")
    var app: GatedApp

    static var parameterSummary: some ParameterSummary {
        Summary("Ask reason for \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Model.shared.pending = app
        return .result()
    }
}
