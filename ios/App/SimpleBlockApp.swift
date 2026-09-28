import SwiftUI

@main
struct SimpleBlockApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

/// The prompt while an app is pending, Home otherwise.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let model = Model.shared

    var body: some View {
        Group {
            if let app = model.pending {
                PromptView(app: app).id(app)
            } else {
                HomeView()
            }
        }
        // Leaving the app drops the prompt. Only from active/inactive: the intent sets `pending` while we're already
        // in the background, right before coming forward.
        .onChange(of: scenePhase) { old, new in
            if new == .background && old != .background { model.pending = nil }
        }
        // simpleblock://gate/signal shows the prompt, for testing.
        .onOpenURL { url in
            guard url.host() == "gate", let app = GatedApp(rawValue: url.lastPathComponent) else { return }
            model.pending = app
        }
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") {}
        }
    }
}
