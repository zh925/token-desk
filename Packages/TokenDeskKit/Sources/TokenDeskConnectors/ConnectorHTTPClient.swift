import Foundation
import TokenDeskCore

/// Redacted HTTP response passed from an injectable transport to a Connector.
public struct ConnectorHTTPResponse: Sendable {
    /// Raw bytes retained only until the private DTO boundary decodes them.
    public let data: Data
    /// HTTP status code used for normalized error mapping.
    public let statusCode: Int
    /// Lowercased, non-secret response headers needed for policies such as `Retry-After`.
    public let headers: [String: String]

    /// Creates a response value without interpreting or logging its body.
    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

/// Minimal async HTTP boundary used by concrete Connector contract tests.
public protocol ConnectorHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> ConnectorHTTPResponse
}

/// Production URLSession implementation. It exposes no response bodies in errors.
public struct URLSessionConnectorHTTPClient: ConnectorHTTPClient, Sendable {
    private let session: URLSession

    /// Creates a transport with an injected URLSession for production or protocol-level tests.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Executes a cancellable request and returns a redacted response envelope.
    public func data(for request: URLRequest) async throws -> ConnectorHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw ConnectorError.network
            }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) {
                result, item in
                guard let key = item.key as? String, let value = item.value as? String else {
                    return
                }
                result[key.lowercased()] = value
            }
            return ConnectorHTTPResponse(
                data: data,
                statusCode: response.statusCode,
                headers: headers
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ConnectorError {
            throw error
        } catch {
            throw ConnectorError.network
        }
    }
}

enum ConnectorHTTPStatus {
    static func validate(_ response: ConnectorHTTPResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw ConnectorError.authentication
        case 403:
            throw ConnectorError.permissionDenied
        case 429:
            let seconds = response.headers["retry-after"].flatMap(Double.init)
            throw ConnectorError.rateLimited(
                retryAfter: seconds.map { .seconds(max(0, $0)) }
            )
        case 500...599:
            throw ConnectorError.server(statusCode: response.statusCode)
        default:
            throw ConnectorError.server(statusCode: response.statusCode)
        }
    }
}
