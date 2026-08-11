import Foundation
import SwiftUI

/// Semantic visual tokens for Token Desk's fixed 1-bit interface.
public enum TokenDeskDesign {
    /// Fixed-canvas dimensions shared by platform placement and feature layouts.
    public enum Canvas {
        /// Design-canvas width in logical points.
        public static let width: CGFloat = 1_280
        /// Design-canvas height in logical points.
        public static let height: CGFloat = 720
        /// Height reserved for the global app header.
        public static let headerHeight: CGFloat = 58
        /// Width reserved for the provider list on the Token page.
        public static let providerColumnWidth: CGFloat = 246

        /// The fixed logical canvas size.
        public static var size: CGSize {
            CGSize(width: width, height: height)
        }
    }

    /// Spacing steps used to keep dense layouts aligned to a small scale.
    public enum Spacing {
        /// Two-point separation for tightly grouped marks.
        public static let hairline: CGFloat = 2
        /// Four-point spacing for compact labels.
        public static let extraSmall: CGFloat = 4
        /// Eight-point spacing for related controls.
        public static let small: CGFloat = 8
        /// Twelve-point spacing for component interiors.
        public static let medium: CGFloat = 12
        /// Sixteen-point spacing between component groups.
        public static let large: CGFloat = 16
        /// Twenty-four-point page inset.
        public static let extraLarge: CGFloat = 24
        /// Thirty-two-point separation between page sections.
        public static let section: CGFloat = 32
    }

    /// Pixel-sharp border widths for standard and emphasized edges.
    public enum Border {
        /// One-point divider line.
        public static let hairline: CGFloat = 1
        /// Two-point component outline.
        public static let regular: CGFloat = 2
        /// Three-point selected or focused outline.
        public static let emphasis: CGFloat = 3
    }

    /// Shared interactive-control dimensions.
    public enum Control {
        /// Minimum pointer and keyboard target dimension required by the PRD.
        public static let minimumInteractiveDimension: CGFloat = 40
    }

    /// Semantic grayscale colors used throughout product UI.
    public enum Palette {
        /// Primary text, border, and selected-surface color.
        public static let ink = TokenDeskColor(red: 0x11, green: 0x11, blue: 0x11)
        /// Primary background and inverted-text color.
        public static let paper = TokenDeskColor(red: 0xFF, green: 0xFF, blue: 0xFF)
        /// Secondary surface color for inactive regions.
        public static let surfaceMuted = TokenDeskColor(red: 0xE7, green: 0xE7, blue: 0xE7)
        /// Stronger surface color reserved for decoration rather than body text.
        public static let surfaceMid = TokenDeskColor(red: 0xBC, green: 0xBC, blue: 0xBC)
        /// Secondary text color that retains WCAG AA contrast on paper.
        public static let inkMuted = TokenDeskColor(red: 0x5B, green: 0x5B, blue: 0x5B)
    }
}

/// An inspectable sRGB value used to enforce contrast requirements in tests.
public struct TokenDeskColor: Equatable, Sendable {
    /// Red sRGB component in the closed range zero through one.
    public let red: Double
    /// Green sRGB component in the closed range zero through one.
    public let green: Double
    /// Blue sRGB component in the closed range zero through one.
    public let blue: Double
    /// Alpha component in the closed range zero through one.
    public let opacity: Double

    /// Creates a color from integer sRGB components.
    public init(red: UInt8, green: UInt8, blue: UInt8, opacity: Double = 1) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.opacity = opacity
    }

    /// SwiftUI representation of the semantic color.
    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// WCAG relative luminance of the opaque sRGB components.
    public var relativeLuminance: Double {
        (0.2126 * Self.linearized(red)) + (0.7152 * Self.linearized(green))
            + (0.0722 * Self.linearized(blue))
    }

    /// Returns the WCAG contrast ratio between this color and another color.
    public func contrastRatio(against other: TokenDeskColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func linearized(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}

/// Product typography roles and their five-inch-screen size floors.
public enum TokenDeskTextStyle: CaseIterable, Sendable {
    case clock
    case primaryMetric
    case pageTitle
    case cardTitle
    case body
    case control
    case auxiliary

    /// Font size in logical points.
    public var size: CGFloat {
        switch self {
        case .clock: 72
        case .primaryMetric: 48
        case .pageTitle: 26
        case .cardTitle: 20
        case .body: 15
        case .control: 14
        case .auxiliary: 11
        }
    }

    /// SwiftUI font configured for the text role.
    public var font: Font {
        switch self {
        case .clock, .primaryMetric:
            Font.system(size: size, weight: .bold, design: .monospaced)
        case .pageTitle, .cardTitle, .control:
            Font.system(size: size, weight: .bold, design: .rounded)
        case .body:
            Font.system(size: size, weight: .regular, design: .rounded)
        case .auxiliary:
            Font.system(size: size, weight: .medium, design: .monospaced)
        }
    }
}
