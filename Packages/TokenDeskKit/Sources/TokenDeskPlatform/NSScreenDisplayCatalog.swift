import AppKit
import CoreGraphics

@MainActor
protocol DisplayCatalog: AnyObject {
    func currentDisplays() -> [DisplayDescriptor]
}

@MainActor
final class NSScreenDisplayCatalog: DisplayCatalog {
    func currentDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap(makeDescriptor)
    }

    private func makeDescriptor(for screen: NSScreen) -> DisplayDescriptor? {
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else {
            return nil
        }

        let displayId = CGDirectDisplayID(number.uint32Value)
        let mode = CGDisplayCopyDisplayMode(displayId)
        return DisplayDescriptor(
            runtimeId: displayId,
            name: screen.localizedName,
            vendorNumber: CGDisplayVendorNumber(displayId),
            modelNumber: CGDisplayModelNumber(displayId),
            logicalSize: mode.map {
                DisplaySize(width: Double($0.width), height: Double($0.height))
            },
            pixelSize: mode.map {
                DisplaySize(width: Double($0.pixelWidth), height: Double($0.pixelHeight))
            },
            backingScaleFactor: screen.backingScaleFactor,
            frame: DisplayFrame(screen.frame),
            visibleFrame: DisplayFrame(screen.visibleFrame),
            isMain: screen == NSScreen.main
        )
    }
}

extension DisplayFrame {
    init(_ rectangle: CGRect) {
        self.init(
            originX: rectangle.origin.x,
            originY: rectangle.origin.y,
            width: rectangle.width,
            height: rectangle.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }
}
