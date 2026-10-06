import SwiftUI

/// Zone tab: "Focus" in thin white type on black, nothing else. For the Settings window parked on a second display,
/// sidebar hidden with ⌘B. It never shows time left and a click does nothing: focus starts from the Focus tab only.
struct ZonePane: View {
    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 100
            ZStack {
                Color.black
                Text("Focus")
                    .font(.system(size: 18 * unit, weight: .ultraLight))
                    .tracking(2 * unit)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .ignoresSafeArea()
        .navigationTitle("Zone")
    }
}
