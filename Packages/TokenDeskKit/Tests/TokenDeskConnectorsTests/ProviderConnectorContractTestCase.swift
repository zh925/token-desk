import Foundation
import TokenDeskCore
import XCTest

/// Reusable assertions that every concrete Provider Connector test suite must invoke.
///
/// A concrete suite supplies a sanitized connector and account, then calls
/// ``assertConnectorContract(_:account:interval:)`` from one of its test methods.
class ProviderConnectorContractTestCase: XCTestCase {
    /// Verifies that declared capabilities and explicit unsupported results agree.
    func assertConnectorContract(
        _ connector: any ProviderConnector,
        account: AccountReference,
        interval: DateInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertEqual(
            connector.descriptor.id,
            account.providerID,
            "The contract fixture must use an account owned by the connector",
            file: file,
            line: line
        )

        try await connector.validateCredentials(for: account)
        _ = try await connector.fetchAccounts()

        let reads: [(ProviderCapability, ConnectorReadState)] = [
            (.plan, try await connector.fetchPlan(for: account).state),
            (.usage, try await connector.fetchUsage(for: account, in: interval).state),
            (.cost, try await connector.fetchCosts(for: account, in: interval).state),
            (.balance, try await connector.fetchBalance(for: account).state),
        ]

        for (capability, state) in reads {
            if connector.descriptor.capabilities.contains(capability) {
                XCTAssertNotEqual(
                    state,
                    .unsupported,
                    "A declared capability cannot return unsupported",
                    file: file,
                    line: line
                )
            } else {
                XCTAssertEqual(
                    state,
                    .unsupported,
                    "An undeclared capability must return unsupported, not empty",
                    file: file,
                    line: line
                )
            }
        }

        let health = await connector.fetchHealth()
        XCTAssertEqual(health.providerID, connector.descriptor.id, file: file, line: line)
    }
}
