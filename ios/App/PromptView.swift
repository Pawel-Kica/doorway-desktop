import SwiftUI

/// "Why open Signal?": a reason with enough words opens the app, "Never mind" goes to the Home Screen.
struct PromptView: View {
    let app: GatedApp
    private let model = Model.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let state = model.state
        let required = state.requiredWords(now: .now)
        let words = wordCount(text)
        VStack(alignment: .leading, spacing: 12) {
            Text("Why open \(app.name)?")
                .font(.largeTitle.bold())
            Text(quotaLine(state))
                .foregroundStyle(.secondary)
            TextField("Your reason", text: $text, axis: .vertical)
                .lineLimit(4...8)
                .focused($focused)
                .padding(12)
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("reason")
            Text("\(words) / \(required) words")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(words >= required ? .green : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("words")
            Spacer()
            Button {
                model.open(app, reason: text.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Open \(app.name)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(words < required)
            .accessibilityIdentifier("open")
            Button {
                model.resist(app)
            } label: {
                Text("Never mind").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding()
        .onAppear { focused = true }
    }

    /// "Short reason 3 of 5 today", or the long one once they're used up.
    private func quotaLine(_ state: GateState) -> String {
        let limit = state.settings.shortPerDay
        let opens = state.opensToday(now: .now)
        if limit == 0 { return "Every reason is a long one" }
        if opens < limit { return "Short reason \(opens + 1) of \(limit) today" }
        return "\(limit) short reasons used today, write a long one"
    }
}
