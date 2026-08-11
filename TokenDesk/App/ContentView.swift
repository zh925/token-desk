import SwiftUI
import TokenDeskDesign

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            catalog
        }
        .frame(width: TokenDeskDesign.Canvas.width, height: TokenDeskDesign.Canvas.height)
        .background(TokenDeskDesign.Palette.surfaceMid.color)
        .foregroundStyle(TokenDeskDesign.Palette.ink.color)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design-system-canvas")
    }

    private var header: some View {
        HStack(spacing: TokenDeskDesign.Spacing.large) {
            Text("TD")
                .font(TokenDeskTextStyle.control.font)
                .foregroundStyle(TokenDeskDesign.Palette.paper.color)
                .frame(width: 32, height: 32)
                .background(TokenDeskDesign.Palette.ink.color)
                .accessibilityHidden(true)

            Text("Token Desk")
                .font(TokenDeskTextStyle.cardTitle.font)

            Spacer()

            TokenDeskStatusBadge(.connected)
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

    private var catalog: some View {
        VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.large) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.extraSmall) {
                    Text("TokenDeskDesign")
                        .font(TokenDeskTextStyle.pageTitle.font)
                    Text("Design system ready")
                        .font(TokenDeskTextStyle.body.font)
                }
                Spacer()
                Text("1280 × 720 / 1-BIT UI")
                    .font(TokenDeskTextStyle.auxiliary.font)
            }

            HStack(spacing: TokenDeskDesign.Spacing.large) {
                TokenDeskPanel("TYPE") {
                    VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                        Text("10:09")
                            .font(TokenDeskTextStyle.clock.font)
                        Text("72%")
                            .font(TokenDeskTextStyle.primaryMetric.font)
                        Text("Readable body text at 15 px")
                            .font(TokenDeskTextStyle.body.font)
                        Text("AUXILIARY TEXT / 11 PX")
                            .font(TokenDeskTextStyle.auxiliary.font)
                    }
                }
                .frame(width: 384)

                TokenDeskPanel("PATTERN") {
                    VStack(spacing: TokenDeskDesign.Spacing.medium) {
                        patternSample(.diagonal, label: "DIAGONAL")
                        patternSample(.dots, label: "DOTS")
                        patternSample(.horizontal, label: "LINES")
                    }
                }
                .frame(width: 310)

                TokenDeskPanel("CONTROLS") {
                    VStack(alignment: .leading, spacing: TokenDeskDesign.Spacing.medium) {
                        HStack(spacing: TokenDeskDesign.Spacing.small) {
                            Button("Standard") {}
                                .buttonStyle(TokenDeskButtonStyle())
                                .accessibilityIdentifier("standard-button")
                            Button("Selected") {}
                                .buttonStyle(TokenDeskButtonStyle(isSelected: true))
                        }

                        HStack(spacing: TokenDeskDesign.Spacing.small) {
                            Button("Disabled") {}
                                .buttonStyle(TokenDeskButtonStyle())
                                .disabled(true)
                            TokenDeskStatusBadge(.syncing)
                        }

                        HStack(spacing: TokenDeskDesign.Spacing.small) {
                            TokenDeskStatusBadge(.stale)
                            TokenDeskStatusBadge(.error)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(TokenDeskDesign.Spacing.extraLarge)
        .background {
            TokenDeskPatternFill(
                .dots,
                foreground: TokenDeskDesign.Palette.surfaceMid.color,
                background: TokenDeskDesign.Palette.surfaceMuted.color
            )
        }
    }

    private func patternSample(_ pattern: TokenDeskPattern, label: String) -> some View {
        ZStack {
            TokenDeskPatternFill(pattern)
            Text(label)
                .font(TokenDeskTextStyle.auxiliary.font)
                .padding(.horizontal, TokenDeskDesign.Spacing.small)
                .background(TokenDeskDesign.Palette.paper.color)
        }
        .frame(height: 78)
        .overlay {
            Rectangle()
                .stroke(
                    TokenDeskDesign.Palette.ink.color,
                    lineWidth: TokenDeskDesign.Border.regular
                )
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 720)
}
