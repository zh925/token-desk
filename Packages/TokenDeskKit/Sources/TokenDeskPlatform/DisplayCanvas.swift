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
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1_280, geometry.size.height / 720)
            content
                .frame(width: 1_280, height: 720)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
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
