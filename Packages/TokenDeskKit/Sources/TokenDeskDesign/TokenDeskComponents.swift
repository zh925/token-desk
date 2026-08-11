import SwiftUI

/// Visible data and connection states supported by the shared badge component.
public enum TokenDeskStatus: CaseIterable, Equatable, Sendable {
    case connected
    case syncing
    case stale
    case warning
    case error
    case unavailable

    /// User-facing text that communicates the state without color.
    public var label: String {
        switch self {
        case .connected: "Connected"
        case .syncing: "Syncing"
        case .stale: "Stale"
        case .warning: "Warning"
        case .error: "Error"
        case .unavailable: "Unavailable"
        }
    }

    /// One-bit glyph paired with the label and fill treatment.
    public var symbol: String {
        switch self {
        case .connected: "●"
        case .syncing: "◌"
        case .stale: "◫"
        case .warning: "!"
        case .error: "×"
        case .unavailable: "–"
        }
    }

    fileprivate var pattern: TokenDeskPattern? {
        switch self {
        case .connected: nil
        case .syncing: .dots
        case .stale: .diagonal
        case .warning: .horizontal
        case .error: .diagonal
        case .unavailable: .dots
        }
    }
}

/// A status badge that combines text, symbol, and pattern for redundant communication.
public struct TokenDeskStatusBadge: View {
    private let status: TokenDeskStatus

    /// Creates a badge for a visible status.
    public init(_ status: TokenDeskStatus) {
        self.status = status
    }

    /// The high-contrast badge content.
    public var body: some View {
        HStack(spacing: TokenDeskDesign.Spacing.small) {
            statusMark
                .frame(width: 20, height: 20)

            Text(status.label)
                .font(TokenDeskTextStyle.control.font)
                .lineLimit(1)
        }
        .foregroundStyle(TokenDeskDesign.Palette.ink.color)
        .padding(.horizontal, TokenDeskDesign.Spacing.medium)
        .frame(minHeight: TokenDeskDesign.Control.minimumInteractiveDimension)
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle()
                .stroke(
                    TokenDeskDesign.Palette.ink.color,
                    lineWidth: TokenDeskDesign.Border.regular
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.label)")
    }

    @ViewBuilder
    private var statusMark: some View {
        ZStack {
            if let pattern = status.pattern {
                TokenDeskPatternFill(pattern)
            } else {
                TokenDeskDesign.Palette.ink.color
            }

            Text(status.symbol)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(
                    status == .connected
                        ? TokenDeskDesign.Palette.paper.color
                        : TokenDeskDesign.Palette.ink.color
                )
        }
        .overlay {
            Rectangle()
                .stroke(
                    TokenDeskDesign.Palette.ink.color,
                    lineWidth: TokenDeskDesign.Border.regular
                )
        }
    }
}

/// Macintosh-style button states for navigation and actions.
public struct TokenDeskButtonStyle: ButtonStyle {
    private let isSelected: Bool

    /// Creates a button style, optionally rendered as the current selection.
    public init(isSelected: Bool = false) {
        self.isSelected = isSelected
    }

    /// Builds the hover, pressed, disabled, selected, and keyboard-focus states.
    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct ButtonBody: View {
        let configuration: Configuration
        let isSelected: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @FocusState private var isFocused: Bool
        @State private var isHovered = false

        private var isInverted: Bool {
            isEnabled && (isSelected || isHovered || configuration.isPressed)
        }

        var body: some View {
            configuration.label
                .font(TokenDeskTextStyle.control.font)
                .lineLimit(1)
                .padding(.horizontal, TokenDeskDesign.Spacing.medium)
                .frame(
                    minWidth: TokenDeskDesign.Control.minimumInteractiveDimension,
                    minHeight: TokenDeskDesign.Control.minimumInteractiveDimension
                )
                .foregroundStyle(foregroundColor)
                .background(backgroundColor)
                .overlay {
                    Rectangle()
                        .stroke(
                            TokenDeskDesign.Palette.ink.color,
                            lineWidth: isFocused
                                ? TokenDeskDesign.Border.emphasis
                                : TokenDeskDesign.Border.regular
                        )
                }
                .overlay(alignment: .bottomTrailing) {
                    if configuration.isPressed {
                        Rectangle()
                            .fill(TokenDeskDesign.Palette.paper.color)
                            .frame(width: 5, height: 5)
                            .padding(3)
                    }
                }
                .contentShape(Rectangle())
                .focusable()
                .focused($isFocused)
                .onHover { isHovered = $0 }
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.08),
                    value: isHovered
                )
                .opacity(isEnabled ? 1 : 0.72)
        }

        private var foregroundColor: Color {
            isInverted
                ? TokenDeskDesign.Palette.paper.color
                : TokenDeskDesign.Palette.ink.color
        }

        private var backgroundColor: Color {
            if !isEnabled {
                return TokenDeskDesign.Palette.surfaceMuted.color
            }
            return isInverted
                ? TokenDeskDesign.Palette.ink.color
                : TokenDeskDesign.Palette.paper.color
        }
    }
}

/// A bordered content panel with a patterned, high-contrast title bar.
public struct TokenDeskPanel<Content: View>: View {
    private let title: String
    private let content: Content

    /// Creates a panel with a title and content builder.
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// The bordered panel content.
    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                TokenDeskPatternFill(.horizontal)
                Text(title)
                    .font(TokenDeskTextStyle.cardTitle.font)
                    .padding(.horizontal, TokenDeskDesign.Spacing.medium)
                    .background(TokenDeskDesign.Palette.paper.color)
            }
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TokenDeskDesign.Palette.ink.color)
                    .frame(height: TokenDeskDesign.Border.regular)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(TokenDeskDesign.Spacing.large)
        }
        .background(TokenDeskDesign.Palette.paper.color)
        .overlay {
            Rectangle()
                .stroke(
                    TokenDeskDesign.Palette.ink.color,
                    lineWidth: TokenDeskDesign.Border.regular
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
