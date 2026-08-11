import AppKit
import SwiftUI
import TokenDeskFeatures

struct ContentView: View {
    @State private var clock: DashboardClock

    @MainActor
    init(clock: DashboardClock = DashboardClock()) {
        _clock = State(initialValue: clock)
    }

    var body: some View {
        TokenDeskAppShell(clock: clock)
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )
            ) { _ in
                clock.resume()
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 720)
}
