import Foundation

/// A display size expressed in either logical points or physical pixels.
public struct DisplaySize: Codable, Hashable, Sendable {
    /// Horizontal extent.
    public let width: Double
    /// Vertical extent.
    public let height: Double

    /// Creates a size from horizontal and vertical extents.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A display-aligned rectangle in the global AppKit coordinate space.
public struct DisplayFrame: Codable, Hashable, Sendable {
    /// Horizontal origin in the global display coordinate space.
    public let originX: Double
    /// Vertical origin in the global display coordinate space.
    public let originY: Double
    /// Rectangle width in points.
    public let width: Double
    /// Rectangle height in points.
    public let height: Double

    /// Creates a frame in the global display coordinate space.
    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

/// A privacy-minimized snapshot of one currently connected display.
///
/// `runtimeId` is suitable for selecting a screen in the current session only. Persistent
/// matching uses ``fingerprint`` and never relies on the runtime identifier alone.
public struct DisplayDescriptor: Identifiable, Equatable, Sendable {
    /// The transient Core Graphics identifier for the current connection.
    public let runtimeId: UInt32
    /// The user-visible display name reported by AppKit.
    public let name: String
    /// The vendor field reported by Core Graphics, which may be zero or generic.
    public let vendorNumber: UInt32
    /// The model field reported by Core Graphics, which may be zero or generic.
    public let modelNumber: UInt32
    /// The active mode's logical pixel size when Core Graphics exposes it.
    public let logicalSize: DisplaySize?
    /// The active mode's physical pixel size when Core Graphics exposes it.
    public let pixelSize: DisplaySize?
    /// The AppKit backing scale between logical points and backing pixels.
    public let backingScaleFactor: Double
    /// The full display bounds in global AppKit coordinates.
    public let frame: DisplayFrame
    /// The display bounds excluding the menu bar and Dock.
    public let visibleFrame: DisplayFrame
    /// Whether AppKit currently treats this display as the main screen.
    public let isMain: Bool

    /// The transient identifier used by SwiftUI lists during this connection.
    public var id: UInt32 { runtimeId }

    /// The composite, non-secret identity persisted after a manual selection.
    public var fingerprint: DisplayFingerprint {
        DisplayFingerprint(
            normalizedName: name.displayFingerprintComponent,
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            logicalSize: logicalSize,
            pixelSize: pixelSize
        )
    }

    /// Creates a privacy-minimized display snapshot from public AppKit fields.
    public init(
        runtimeId: UInt32,
        name: String,
        vendorNumber: UInt32,
        modelNumber: UInt32,
        logicalSize: DisplaySize?,
        pixelSize: DisplaySize?,
        backingScaleFactor: Double,
        frame: DisplayFrame,
        visibleFrame: DisplayFrame,
        isMain: Bool
    ) {
        self.runtimeId = runtimeId
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.logicalSize = logicalSize
        self.pixelSize = pixelSize
        self.backingScaleFactor = backingScaleFactor
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

/// A composite display identity that intentionally excludes transient display IDs and EDID size.
public struct DisplayFingerprint: Codable, Equatable, Sendable {
    /// The case-folded, trimmed display name.
    public let normalizedName: String
    /// The vendor field captured at manual selection time.
    public let vendorNumber: UInt32
    /// The model field captured at manual selection time.
    public let modelNumber: UInt32
    /// The active logical mode captured at manual selection time.
    public let logicalSize: DisplaySize?
    /// The active physical mode captured at manual selection time.
    public let pixelSize: DisplaySize?

    /// Creates a composite fingerprint without a transient ID, serial number, or physical size.
    public init(
        normalizedName: String,
        vendorNumber: UInt32,
        modelNumber: UInt32,
        logicalSize: DisplaySize?,
        pixelSize: DisplaySize?
    ) {
        self.normalizedName = normalizedName.displayFingerprintComponent
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.logicalSize = logicalSize
        self.pixelSize = pixelSize
    }
}

extension String {
    fileprivate var displayFingerprintComponent: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
