import AppKit

struct DisplayWindowLayout {
    static let designSize = DisplaySize(width: 1_280, height: 720)

    static func targetFrame(for display: DisplayDescriptor) -> DisplayFrame {
        display.frame
    }

    static func fallbackFrame(for display: DisplayDescriptor) -> DisplayFrame {
        let available = display.visibleFrame
        let scale = min(
            1,
            available.width / designSize.width,
            available.height / designSize.height
        )
        let width = designSize.width * scale
        let height = designSize.height * scale
        return DisplayFrame(
            originX: available.originX + (available.width - width) / 2,
            originY: available.originY + (available.height - height) / 2,
            width: width,
            height: height
        )
    }
}

@MainActor
protocol DisplayWindowPositioning: AnyObject {
    func attach(window: NSWindow)
    func position(on display: DisplayDescriptor, isFallback: Bool)
}

@MainActor
final class AppKitDisplayWindowPositioner: DisplayWindowPositioning {
    private struct PlacementRequest {
        let display: DisplayDescriptor
        let isFallback: Bool
    }

    private weak var window: NSWindow?
    private var originalStyleMask: NSWindow.StyleMask?
    private var originalCollectionBehavior: NSWindow.CollectionBehavior?
    private var pendingRequest: PlacementRequest?
    private var placementTask: Task<Void, Never>?

    func attach(window: NSWindow) {
        if self.window !== window {
            self.window = window
            originalStyleMask = window.styleMask
            originalCollectionBehavior = window.collectionBehavior
        }
    }

    func position(on display: DisplayDescriptor, isFallback: Bool) {
        pendingRequest = PlacementRequest(display: display, isFallback: isFallback)
        guard placementTask == nil else {
            return
        }

        placementTask = Task { @MainActor [weak self] in
            await Task.yield()
            self?.applyPendingPlacement()
        }
    }

    private func applyPendingPlacement() {
        placementTask = nil
        guard let request = pendingRequest else {
            return
        }
        pendingRequest = nil

        guard let window else {
            return
        }

        if request.isFallback {
            if let originalStyleMask {
                window.styleMask = originalStyleMask
            }
            if let originalCollectionBehavior {
                window.collectionBehavior = originalCollectionBehavior
            }
            window.isMovable = true
        } else {
            window.styleMask = [.borderless]
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovable = false
        }

        let frame =
            request.isFallback
            ? DisplayWindowLayout.fallbackFrame(for: request.display)
            : DisplayWindowLayout.targetFrame(for: request.display)
        window.setFrame(frame.cgRect, display: true, animate: false)
    }
}
