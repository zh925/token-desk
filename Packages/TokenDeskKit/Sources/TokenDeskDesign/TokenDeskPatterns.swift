import SwiftUI

/// Supported high-contrast, one-bit pattern treatments.
public enum TokenDeskPattern: String, CaseIterable, Sendable {
    case diagonal
    case dots
    case horizontal
}

/// A deterministic 1-bit fill. Patterns communicate state without relying on color.
public struct TokenDeskPatternFill: View {
    private let pattern: TokenDeskPattern
    private let foreground: Color
    private let background: Color

    /// Creates a pattern fill using semantic ink and paper by default.
    public init(
        _ pattern: TokenDeskPattern,
        foreground: Color = TokenDeskDesign.Palette.ink.color,
        background: Color = TokenDeskDesign.Palette.paper.color
    ) {
        self.pattern = pattern
        self.foreground = foreground
        self.background = background
    }

    /// Draws the selected pattern without exposing it to accessibility navigation.
    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

            switch pattern {
            case .diagonal:
                drawDiagonal(in: &context, size: size)
            case .dots:
                drawDots(in: &context, size: size)
            case .horizontal:
                drawHorizontal(in: &context, size: size)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func drawDiagonal(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for offset in stride(from: -size.height, through: size.width, by: 8) {
            path.move(to: CGPoint(x: offset, y: size.height))
            path.addLine(to: CGPoint(x: offset + size.height, y: 0))
        }
        context.stroke(path, with: .color(foreground), lineWidth: 1)
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        for x in stride(from: 2.0, through: size.width, by: 6) {
            for y in stride(from: 2.0, through: size.height, by: 6) {
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                    with: .color(foreground)
                )
            }
        }
    }

    private func drawHorizontal(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for y in stride(from: 1.0, through: size.height, by: 5) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(foreground), lineWidth: 1)
    }
}
