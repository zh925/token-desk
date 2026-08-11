import SwiftUI
import TokenDeskPlatform

@main
struct TokenDeskApp: App {
    @StateObject private var displayController = DisplayController()

    var body: some Scene {
        WindowGroup {
            DisplayCanvas {
                ContentView()
            }
            .background(DisplayWindowAttachment(controller: displayController))
            .onAppear {
                displayController.start()
            }
            .onDisappear {
                displayController.stop()
            }
        }
        .defaultSize(width: 1_280, height: 720)
    }
}
