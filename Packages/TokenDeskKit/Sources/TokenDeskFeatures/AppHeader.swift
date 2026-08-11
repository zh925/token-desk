import SwiftUI
import TokenDeskDesign

/// Fixed application header with primary routing and the only settings entry.
public struct AppHeader: View {
    @Bindable private var router: AppRouter

    /// Creates a header bound to the application router.
    public init(router: AppRouter) {
        self.router = router
    }

    /// The 58-point global header.
    public var body: some View {
        HStack(spacing: TokenDeskDesign.Spacing.large) {
            brand

            HStack(spacing: TokenDeskDesign.Spacing.small) {
                ForEach(AppRoute.primaryNavigation, id: \.self) { route in
                    navigationButton(for: route)
                }
            }

            Spacer()

            TokenDeskStatusBadge(.connected)

            Text("最后更新 10:09")
                .font(TokenDeskTextStyle.auxiliary.font)

            Button("同步") {}
                .buttonStyle(TokenDeskButtonStyle())
                .accessibilityIdentifier("sync-button")

            Button("设置") {
                router.select(.settings)
            }
            .buttonStyle(TokenDeskButtonStyle(isSelected: router.route == .settings))
            .accessibilityIdentifier("settings-button")
            .accessibilityHint("打开所有应用配置")
        }
        .padding(.horizontal, TokenDeskDesign.Spacing.extraLarge)
        .frame(height: TokenDeskDesign.Canvas.headerHeight)
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokenDeskDesign.Palette.ink.color)
                .frame(height: TokenDeskDesign.Border.emphasis)
        }
    }

    private var brand: some View {
        HStack(spacing: TokenDeskDesign.Spacing.small) {
            Text("TD")
                .font(TokenDeskTextStyle.control.font)
                .foregroundStyle(TokenDeskDesign.Palette.paper.color)
                .frame(width: 32, height: 32)
                .background(TokenDeskDesign.Palette.ink.color)
                .accessibilityHidden(true)

            Text("Token Desk")
                .font(TokenDeskTextStyle.cardTitle.font)
        }
        .frame(minWidth: 210, alignment: .leading)
    }

    private func navigationButton(for route: AppRoute) -> some View {
        Button(route.title) {
            router.select(route)
        }
        .buttonStyle(TokenDeskButtonStyle(isSelected: router.route == route))
        .keyboardShortcut(KeyEquivalent(route.keyboardShortcut ?? "1"), modifiers: [])
        .accessibilityIdentifier(route.accessibilityIdentifier)
        .accessibilityHint("快捷键 \(String(route.keyboardShortcut ?? "1"))")
    }
}
