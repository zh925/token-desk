import AppKit
import CoreGraphics
import Foundation

private struct Size: Codable {
    let width: Double
    let height: Double
}

private struct Rectangle: Codable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double

    init(_ rectangle: CGRect) {
        originX = rectangle.origin.x
        originY = rectangle.origin.y
        width = rectangle.width
        height = rectangle.height
    }
}

private struct DisplaySnapshot: Codable {
    let displayID: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let isOnline: Bool
    let isActive: Bool
    let framePoints: Rectangle
    let visibleFramePoints: Rectangle
    let backingScaleFactor: Double
    let modeLogicalPixels: Size?
    let modePhysicalPixels: Size?
    let refreshRateHz: Double?
    let physicalSizeMillimeters: Size
    let rotationDegrees: Double
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
}

private struct SnapshotEnvelope: Codable {
    let recordedAt: String
    let targetName: String?
    let displays: [DisplaySnapshot]
}

private enum EventKind: String, Codable {
    case baseline
    case disconnected
    case reconnected
    case willSleep = "will_sleep"
    case didWake = "did_wake"
    case wakeRecovered = "wake_recovered"
}

private struct ProbeEvent: Codable {
    let recordedAt: String
    let monotonicSeconds: Double
    let event: EventKind
    let targetName: String
    let targetPresent: Bool
    let recoverySeconds: Double?
    let targetDisplays: [DisplaySnapshot]
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case cannotCreateOutput(String)
    case outputAlreadyExists(String)
    case cannotEncode

    var description: String {
        switch self {
        case .invalidArguments(let detail):
            return detail
        case .cannotCreateOutput(let path):
            return "Cannot create output file: \(path)"
        case .outputAlreadyExists(let path):
            return "Output file already exists: \(path)"
        case .cannotEncode:
            return "Cannot encode probe output as JSON"
        }
    }
}

@MainActor
private func iso8601String(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

@MainActor
private func snapshots(targetName: String? = nil) -> [DisplaySnapshot] {
    NSScreen.screens.compactMap { screen in
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
        else {
            return nil
        }

        if let targetName,
            screen.localizedName.localizedCaseInsensitiveContains(targetName) == false
        {
            return nil
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let mode = CGDisplayCopyDisplayMode(displayID)
        let physicalSize = CGDisplayScreenSize(displayID)

        return DisplaySnapshot(
            displayID: displayID,
            name: screen.localizedName,
            isMain: screen == NSScreen.main,
            isOnline: CGDisplayIsOnline(displayID) != 0,
            isActive: CGDisplayIsActive(displayID) != 0,
            framePoints: Rectangle(screen.frame),
            visibleFramePoints: Rectangle(screen.visibleFrame),
            backingScaleFactor: screen.backingScaleFactor,
            modeLogicalPixels: mode.map {
                Size(width: Double($0.width), height: Double($0.height))
            },
            modePhysicalPixels: mode.map {
                Size(width: Double($0.pixelWidth), height: Double($0.pixelHeight))
            },
            refreshRateHz: mode.flatMap { $0.refreshRate > 0 ? $0.refreshRate : nil },
            physicalSizeMillimeters: Size(
                width: physicalSize.width,
                height: physicalSize.height
            ),
            rotationDegrees: CGDisplayRotation(displayID),
            vendorNumber: CGDisplayVendorNumber(displayID),
            modelNumber: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID)
        )
    }
}

private func encodedJSON<T: Encodable>(_ value: T, prettyPrinted: Bool) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    guard let newline = "\n".data(using: .utf8) else {
        throw ProbeError.cannotEncode
    }
    var data = try encoder.encode(value)
    data.append(newline)
    return data
}

@MainActor
private final class DisplayWatcher: NSObject {
    private let targetName: String
    private let outputHandle: FileHandle
    private let interval: TimeInterval
    private var targetWasPresent: Bool
    private var disconnectedAt: TimeInterval?
    private var wokeAt: TimeInterval?
    private var timer: Timer?

    init(targetName: String, outputHandle: FileHandle, interval: TimeInterval) {
        self.targetName = targetName
        self.outputHandle = outputHandle
        self.interval = interval
        targetWasPresent = snapshots(targetName: targetName).isEmpty == false
        super.init()
    }

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        record(.baseline)
        timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.run()
    }

    @objc private func poll() {
        let targetIsPresent = snapshots(targetName: targetName).isEmpty == false

        if targetWasPresent && targetIsPresent == false {
            disconnectedAt = ProcessInfo.processInfo.systemUptime
            record(.disconnected)
        } else if targetWasPresent == false && targetIsPresent {
            let elapsed = disconnectedAt.map {
                ProcessInfo.processInfo.systemUptime - $0
            }
            record(.reconnected, recoverySeconds: elapsed)
            disconnectedAt = nil
        }

        if targetIsPresent, let wokeAt {
            record(
                .wakeRecovered,
                recoverySeconds: ProcessInfo.processInfo.systemUptime - wokeAt
            )
            self.wokeAt = nil
        }

        targetWasPresent = targetIsPresent
    }

    @objc private func willSleep() {
        record(.willSleep)
    }

    @objc private func didWake() {
        wokeAt = ProcessInfo.processInfo.systemUptime
        record(.didWake)
    }

    private func record(_ event: EventKind, recoverySeconds: Double? = nil) {
        let targetDisplays = snapshots(targetName: targetName)
        let probeEvent = ProbeEvent(
            recordedAt: iso8601String(from: Date()),
            monotonicSeconds: ProcessInfo.processInfo.systemUptime,
            event: event,
            targetName: targetName,
            targetPresent: targetDisplays.isEmpty == false,
            recoverySeconds: recoverySeconds,
            targetDisplays: targetDisplays
        )

        do {
            try outputHandle.write(contentsOf: encodedJSON(probeEvent, prettyPrinted: false))
            try outputHandle.synchronize()
        } catch {
            FileHandle.standardError.write(
                Data("Failed to write probe event: \(error)\n".utf8)
            )
        }
    }

}

private struct Arguments {
    enum Command {
        case snapshot
        case watch
    }

    let command: Command
    let targetName: String?
    let outputPath: String?
    let interval: TimeInterval

    init(_ values: [String]) throws {
        guard let commandValue = values.first else {
            throw ProbeError.invalidArguments(Self.usage)
        }

        switch commandValue {
        case "snapshot":
            command = .snapshot
        case "watch":
            command = .watch
        default:
            throw ProbeError.invalidArguments("Unknown command: \(commandValue)\n\n\(Self.usage)")
        }

        var parsedTargetName: String?
        var parsedOutputPath: String?
        var parsedInterval = 0.2
        var index = 1

        while index < values.count {
            guard index + 1 < values.count else {
                throw ProbeError.invalidArguments("Missing value for \(values[index])")
            }

            let option = values[index]
            let value = values[index + 1]
            switch option {
            case "--target-name":
                parsedTargetName = value
            case "--output":
                parsedOutputPath = value
            case "--interval":
                guard let interval = TimeInterval(value), interval >= 0.1 else {
                    throw ProbeError.invalidArguments("--interval must be at least 0.1 seconds")
                }
                parsedInterval = interval
            default:
                throw ProbeError.invalidArguments("Unknown option: \(option)")
            }
            index += 2
        }

        if command == .watch {
            guard parsedTargetName?.isEmpty == false else {
                throw ProbeError.invalidArguments("watch requires --target-name")
            }
            guard parsedOutputPath?.isEmpty == false else {
                throw ProbeError.invalidArguments("watch requires --output")
            }
        }

        targetName = parsedTargetName
        outputPath = parsedOutputPath
        interval = parsedInterval
    }

    static let usage = """
        Usage:
          M5DisplayProbe snapshot [--target-name Wokyis]
          M5DisplayProbe watch --target-name Wokyis --output <events.jsonl> [--interval 0.2]
        """
}

@main
private struct M5DisplayProbe {
    @MainActor
    static func main() {
        do {
            let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
            switch arguments.command {
            case .snapshot:
                let envelope = SnapshotEnvelope(
                    recordedAt: iso8601String(from: Date()),
                    targetName: arguments.targetName,
                    displays: snapshots(targetName: arguments.targetName)
                )
                FileHandle.standardOutput.write(
                    try encodedJSON(envelope, prettyPrinted: true)
                )
            case .watch:
                guard
                    let targetName = arguments.targetName,
                    let outputPath = arguments.outputPath
                else {
                    throw ProbeError.invalidArguments(Arguments.usage)
                }

                guard FileManager.default.fileExists(atPath: outputPath) == false else {
                    throw ProbeError.outputAlreadyExists(outputPath)
                }

                guard FileManager.default.createFile(atPath: outputPath, contents: nil),
                    let outputHandle = FileHandle(forWritingAtPath: outputPath)
                else {
                    throw ProbeError.cannotCreateOutput(outputPath)
                }

                DisplayWatcher(
                    targetName: targetName,
                    outputHandle: outputHandle,
                    interval: arguments.interval
                ).start()
            }
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
}
