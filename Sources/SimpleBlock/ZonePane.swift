import SwiftUI

/// Zone tab: "Focus" in thin white type on black, nothing else. For the Settings window parked on a second display,
/// sidebar hidden with ⌘B. It never shows time left. Clicking it while focus is off starts one for the Focus tab's length.
struct ZonePane: View {
    @ObservedObject var model: AppModel
    @AppStorage("focusMinutes") private var minutes = 120
    @State private var hint: String?

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 100
            ZStack {
                Color.black
                Text("Focus")
                    .font(.system(size: 18 * unit, weight: .ultraLight))
                    .tracking(2 * unit)
                    .foregroundStyle(.white.opacity(0.85))
                if let hint {
                    Text(hint).font(.system(size: 2.2 * unit)).foregroundStyle(.white.opacity(0.6))
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 5 * unit)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: start)
        }
        .ignoresSafeArea()
        .navigationTitle("Zone")
    }

    /// Starts focus off a click. With nothing allowed it can't, so it says where to fix that.
    private func start() {
        guard model.focusLeft == 0 else { return }
        model.startFocus(minutes: minutes)
        guard model.focus == nil else { return }
        hint = "Pick apps in the Focus tab first"
        Task {
            try? await Task.sleep(for: .seconds(3))
            hint = nil
        }
    }
}
