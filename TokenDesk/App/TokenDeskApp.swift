import SwiftUI

@main
struct TokenDeskApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1280, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
