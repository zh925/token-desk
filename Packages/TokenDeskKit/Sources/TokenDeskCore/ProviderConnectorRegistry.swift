/// Registry failures that must be resolved at the application composition boundary.
public enum ProviderConnectorRegistryError: Error, Equatable, Sendable {
    /// A configured Provider instance ID was registered more than once.
    case duplicateProvider(ProviderID)
}

/// An actor-isolated registry keyed by configured Provider instance rather than Provider type.
///
/// Multiple instances of one Provider type may coexist. Registration never silently replaces an
/// existing instance, preventing one account configuration from taking over another.
public actor ProviderConnectorRegistry {
    private var connectors: [ProviderID: any ProviderConnector]

    /// Creates a registry and rejects duplicate configured Provider instance IDs.
    public init(connectors: [any ProviderConnector] = []) throws {
        var indexed: [ProviderID: any ProviderConnector] = [:]
        for connector in connectors {
            let providerID = connector.descriptor.id
            guard indexed[providerID] == nil else {
                throw ProviderConnectorRegistryError.duplicateProvider(providerID)
            }
            indexed[providerID] = connector
        }
        self.connectors = indexed
    }

    /// Registers a configured Connector without replacing an existing instance.
    public func register(_ connector: any ProviderConnector) throws {
        let providerID = connector.descriptor.id
        guard connectors[providerID] == nil else {
            throw ProviderConnectorRegistryError.duplicateProvider(providerID)
        }
        connectors[providerID] = connector
    }

    /// Removes and returns a configured Connector, if present.
    @discardableResult
    public func remove(providerID: ProviderID) -> (any ProviderConnector)? {
        connectors.removeValue(forKey: providerID)
    }

    /// Resolves one configured Connector.
    public func connector(for providerID: ProviderID) -> (any ProviderConnector)? {
        connectors[providerID]
    }

    /// Returns immutable descriptors in stable configured-ID order.
    public func descriptors() -> [ProviderDescriptor] {
        connectors.values.map(\.descriptor).sorted {
            $0.id.rawValue < $1.id.rawValue
        }
    }

    /// Returns all registered Connectors for a synchronization coordinator.
    public func allConnectors() -> [any ProviderConnector] {
        connectors.values.sorted {
            $0.descriptor.id.rawValue < $1.descriptor.id.rawValue
        }
    }

    /// Checks all Providers concurrently and retains every Provider's independent health result.
    public func healthSnapshot() async -> [ProviderID: ConnectorHealth] {
        let registered = Array(connectors.values)
        return await withTaskGroup(
            of: (ProviderID, ConnectorHealth).self,
            returning: [ProviderID: ConnectorHealth].self
        ) { group in
            for connector in registered {
                group.addTask {
                    let health = await connector.fetchHealth()
                    return (connector.descriptor.id, health)
                }
            }

            var snapshot: [ProviderID: ConnectorHealth] = [:]
            for await (providerID, health) in group {
                snapshot[providerID] = health
            }
            return snapshot
        }
    }
}
