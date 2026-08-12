import AppKit
import SwiftUI

/// Uniformly scales a fixed 1280×720 dashboard canvas to the attached display window.
public struct DisplayCanvas<Content: View>: View {
    private let content: Content

    /// Creates a fixed-design canvas around dashboard content.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// The uniformly scaled dashboard content.
    public var body: some View {
        DisplayCanvasLayout {
            content
        }
        .modifier(DisplayCanvasScaleEffect())
        .clipped()
    }
}

private struct DisplayCanvasLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: DisplayCanvasScale.designSize)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let content = subviews.first else { return }
        content.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(DisplayCanvasScale.designSize)
        )
    }
}

struct DisplayCanvasScale {
    static let designSize = CGSize(width: 1_280, height: 720)

    static func factor(for containerSize: CGSize) -> CGFloat {
        guard
            containerSize.width.isFinite,
            containerSize.height.isFinite,
            containerSize.width > 0,
            containerSize.height > 0
        else {
            return 0
        }
        return min(
            containerSize.width / designSize.width,
            containerSize.height / designSize.height
        )
    }
}

private struct DisplayCanvasScaleEffect: GeometryEffect {
    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = DisplayCanvasScale.factor(for: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
        return ProjectionTransform(transform)
    }
}

/// Connects the containing SwiftUI window to a ``DisplayController``.
public struct DisplayWindowAttachment: NSViewRepresentable {
    private let controller: DisplayController

    /// Creates a window attachment for a display controller.
    public init(controller: DisplayController) {
        self.controller = controller
    }

    /// Creates the AppKit bridge view used to discover the containing window.
    public func makeNSView(context: Context) -> NSView {
        WindowAttachmentView(controller: controller)
    }

    /// Keeps the bridge view attached; no incremental AppKit state is required.
    public func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class WindowAttachmentView: NSView {
    private let controller: DisplayController

    init(controller: DisplayController) {
        self.controller = controller
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            controller.attach(window: window)
        }
    }
}
