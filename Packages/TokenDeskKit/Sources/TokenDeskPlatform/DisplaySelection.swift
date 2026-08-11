import Foundation

/// How the active target display was chosen.
public enum DisplaySelectionKind: String, Equatable, Sendable {
    case automatic
    case rememberedManualSelection
}

/// Why the dashboard is currently using a safe fallback display.
public enum DisplayFallbackReason: String, Equatable, Sendable {
    case noDisplays
    case automaticTargetMissing
    case preferredDisplayMissing
    case ambiguousMatch
}

/// The current display resolution outcome exposed to settings and diagnostics UI.
public enum DisplayControllerState: Equatable, Sendable {
    case stopped
    case target(DisplayDescriptor, selection: DisplaySelectionKind)
    case fallback(DisplayDescriptor?, reason: DisplayFallbackReason)
}

struct DisplayMatcher {
    private let targetName: String
    private let targetSize: DisplaySize

    init(
        targetName: String = "Wokyis",
        targetSize: DisplaySize = DisplaySize(width: 1_280, height: 720)
    ) {
        self.targetName = targetName
        self.targetSize = targetSize
    }

    func resolve(
        displays: [DisplayDescriptor],
        preferred: DisplayFingerprint?
    ) -> DisplayControllerState {
        guard displays.isEmpty == false else {
            return .fallback(nil, reason: .noDisplays)
        }

        if let preferred {
            return resolveRememberedSelection(displays: displays, preferred: preferred)
        }

        let candidates = displays.filter(isAutomaticCandidate)
        if candidates.count == 1, let candidate = candidates.first {
            return .target(candidate, selection: .automatic)
        }

        return .fallback(
            fallbackDisplay(in: displays),
            reason: candidates.isEmpty ? .automaticTargetMissing : .ambiguousMatch
        )
    }

    private func resolveRememberedSelection(
        displays: [DisplayDescriptor],
        preferred: DisplayFingerprint
    ) -> DisplayControllerState {
        let matches = displays.compactMap { display -> (DisplayDescriptor, Int)? in
            guard let score = matchScore(display.fingerprint, preferred) else {
                return nil
            }
            return (display, score)
        }
        let bestScore = matches.map(\.1).max()
        let bestMatches = matches.filter { $0.1 == bestScore }

        if bestMatches.count == 1, let display = bestMatches.first?.0 {
            return .target(display, selection: .rememberedManualSelection)
        }

        return .fallback(
            fallbackDisplay(in: displays),
            reason: matches.isEmpty ? .preferredDisplayMissing : .ambiguousMatch
        )
    }

    private func matchScore(
        _ candidate: DisplayFingerprint,
        _ preferred: DisplayFingerprint
    ) -> Int? {
        let nameMatches = candidate.normalizedName == preferred.normalizedName
        let hardwareMatches =
            preferred.vendorNumber != 0 && preferred.modelNumber != 0
            && candidate.vendorNumber == preferred.vendorNumber
            && candidate.modelNumber == preferred.modelNumber
        let logicalModeMatches = preferred.logicalSize.map { candidate.logicalSize == $0 } ?? false
        let pixelModeMatches = preferred.pixelSize.map { candidate.pixelSize == $0 } ?? false
        let modeMatches = logicalModeMatches || pixelModeMatches
        let matchedComponents = [
            nameMatches,
            hardwareMatches,
            modeMatches,
        ].filter { $0 }.count

        guard matchedComponents >= 2 else {
            return nil
        }

        return (nameMatches ? 8 : 0) + (hardwareMatches ? 4 : 0)
            + (pixelModeMatches ? 2 : 0) + (logicalModeMatches ? 1 : 0)
    }

    private func isAutomaticCandidate(_ display: DisplayDescriptor) -> Bool {
        let normalizedTargetName = targetName.lowercased()
        let nameMatches = display.name.lowercased().contains(normalizedTargetName)
        let modeMatches = display.logicalSize == targetSize || display.pixelSize == targetSize
        return nameMatches && modeMatches
    }

    private func fallbackDisplay(in displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        displays.first(where: \.isMain) ?? displays.first
    }
}
