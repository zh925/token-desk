import SwiftUI
import TokenDeskConnectors
import TokenDeskCore
import TokenDeskData
import TokenDeskDesign
import TokenDeskFeatures
import TokenDeskPlatform

struct ContentView: View {
    private let modules = [
        TokenDeskCoreModule.name,
        TokenDeskDataModule.name,
        TokenDeskConnectorsModule.name,
        TokenDeskPlatformModule.name,
        TokenDeskDesignModule.name,
        TokenDeskFeaturesModule.name,
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Token Desk")
                .font(.largeTitle.monospaced().bold())
            Text("Project baseline ready")
                .font(.title2.monospaced())
            Text(modules.joined(separator: " • "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityLabel("All application modules are linked")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 720)
}
