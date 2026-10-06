import Observation
import UIKit

/// App-wide state. The intents and the views share `Model.shared`, since the intents run in the app's own process.
@MainActor @Observable
final class Model {
    static let shared = Model()

    private static let key = "state"

    /// Saved to UserDefaults on every change.
    var state: GateState {
        didSet { save() }
    }
    /// The app waiting on a reason. Set by the Gate App intent, shows the prompt while non-nil.
    var pending: GatedApp?
    /// One-off message for an alert, e.g. when the gated app couldn't be opened by URL.
    var notice: String?

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        state = data.flatMap { try? JSONDecoder().decode(GateState.self, from: $0) } ?? GateState()
        // Launch argument `-gate signal` opens straight on the prompt, for simulator screenshots (simctl openurl asks
        // "Open in Doorway?" first, which can't be tapped headless).
        pending = UserDefaults.standard.string(forKey: "gate").flatMap(GatedApp.init(rawValue:))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Logs the reason, unlocks the app and opens it. Opening it fires the automation again, which now lets it through.
    func open(_ app: GatedApp, reason: String) {
        state.open(app, reason: reason, now: .now)
        pending = nil
        Task {
            if await !UIApplication.shared.open(app.url) {
                notice = "\(app.name) is unlocked for \(state.settings.unlockMinutes) min, open it from the Home Screen."
            }
        }
    }

    /// Logs a "Never mind" and goes to the Home Screen.
    func resist(_ app: GatedApp) {
        state.resist(app, now: .now)
        pending = nil
        UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    }
}
