import AppKit
import Foundation
import TokenDeskCore
import UniformTypeIdentifiers

/// Writes an export only to the single destination selected through `NSSavePanel`.
@MainActor
public final class SavePanelHistoryExportService: HistoryExportServicing {
    /// Injectable system-panel boundary returning only a user-approved destination.
    public typealias DestinationPicker =
        @MainActor (
            _ format: HistoryExportFormat,
            _ suggestedFilename: String
        ) async -> URL?
    /// Injectable single-file writer used after destination approval.
    public typealias DataWriter = @MainActor (_ data: Data, _ url: URL) throws -> Void

    private let destinationPicker: DestinationPicker
    private let dataWriter: DataWriter

    /// Creates the production save-panel service.
    public convenience init() {
        self.init(
            destinationPicker: Self.presentPanel,
            dataWriter: { data, url in
                try data.write(to: url, options: .atomic)
            }
        )
    }

    /// Creates an injectable service for cancellation and write-boundary tests.
    public init(
        destinationPicker: @escaping DestinationPicker,
        dataWriter: @escaping DataWriter
    ) {
        self.destinationPicker = destinationPicker
        self.dataWriter = dataWriter
    }

    /// Returns cancellation without touching the filesystem, or writes one selected file.
    public func export(
        data: Data,
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async throws -> HistoryExportResult {
        guard let url = await destinationPicker(format, suggestedFilename) else {
            return .cancelled
        }
        try dataWriter(data, url)
        return .saved(filename: url.lastPathComponent)
    }

    private static func presentPanel(
        format: HistoryExportFormat,
        suggestedFilename: String
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "导出 Token Desk 历史"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "\(suggestedFilename).\(format.filenameExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let contentType = UTType(filenameExtension: format.filenameExtension) {
            panel.allowedContentTypes = [contentType]
        }
        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }
}
