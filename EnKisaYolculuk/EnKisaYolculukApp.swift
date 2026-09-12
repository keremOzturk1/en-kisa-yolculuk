import SwiftUI

@main
struct EnKisaYolculukApp: App {
    @StateObject private var appState = AppState()
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                StationPickerView()
                    .environmentObject(appState)

                if showingSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                // The network parses far faster than this, so the splash is
                // never hiding real work — this duration is purely how long the
                // brand stays on screen.
                try? await Task.sleep(for: .seconds(3.7))
                withAnimation(.easeOut(duration: 0.45)) { showingSplash = false }
            }
        }
    }
}
