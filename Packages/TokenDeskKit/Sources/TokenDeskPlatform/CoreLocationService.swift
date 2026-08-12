import CoreLocation
import Foundation
import TokenDeskCore

/// Errors surfaced by the one-shot, privacy-minimized location service.
public enum CoreLocationServiceError: LocalizedError, Equatable {
    case permissionDenied
    case requestAlreadyRunning
    case locationUnavailable
    case cityRequired
    case cityNotFound

    /// Privacy-safe recovery guidance suitable for settings UI.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "定位权限未开启，可继续使用手工城市。"
        case .requestAlreadyRunning: "定位请求正在进行。"
        case .locationUnavailable: "暂时无法取得当前位置，请使用手工城市。"
        case .cityRequired: "请输入城市名称。"
        case .cityNotFound: "未找到该城市，请检查名称后重试。"
        }
    }
}

/// Requests one current location and never retains a location trail.
@MainActor
public final class CoreLocationService:
    NSObject, LocationServicing, @MainActor CLLocationManagerDelegate
{
    private let manager: CLLocationManager
    private var pendingContinuation: CheckedContinuation<WeatherLocation, any Error>?

    /// Creates the Core Location adapter used by the application composition root.
    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    /// Current normalized Core Location authorization state.
    public var authorizationStatus: PermissionAuthorization {
        Self.authorization(from: manager.authorizationStatus)
    }

    /// Requests when-in-use authorization only as part of this explicit user action.
    public func requestCurrentLocation() async throws -> WeatherLocation {
        guard pendingContinuation == nil else {
            throw CoreLocationServiceError.requestAlreadyRunning
        }
        guard authorizationStatus != .denied, authorizationStatus != .restricted else {
            throw CoreLocationServiceError.permissionDenied
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
                if authorizationStatus == .authorized {
                    manager.requestLocation()
                } else {
                    manager.requestWhenInUseAuthorization()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingRequest()
            }
        }
    }

    /// Geocodes a manually entered city without reading device location.
    public func resolve(city: String) async throws -> WeatherLocation {
        let normalized = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CoreLocationServiceError.cityRequired
        }

        let placemarks = try await CLGeocoder().geocodeAddressString(normalized)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw CoreLocationServiceError.cityNotFound
        }
        return try WeatherLocation(
            key: "manual:\(normalized.lowercased())",
            cityName: normalized,
            latitude: Decimal(coordinate.latitude),
            longitude: Decimal(coordinate.longitude)
        )
    }

    /// Continues or rejects the pending one-shot request after authorization changes.
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingContinuation != nil else { return }
        switch authorizationStatus {
        case .authorized:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: .failure(CoreLocationServiceError.permissionDenied))
        case .notDetermined, .unavailable:
            break
        }
    }

    /// Completes the pending request with only the most recent coarse location.
    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let coordinate = locations.last?.coordinate else {
            finish(with: .failure(CoreLocationServiceError.locationUnavailable))
            return
        }
        do {
            let location = try WeatherLocation(
                key: "current",
                cityName: "当前位置",
                latitude: Decimal(coordinate.latitude),
                longitude: Decimal(coordinate.longitude)
            )
            finish(with: .success(location))
        } catch {
            finish(with: .failure(CoreLocationServiceError.locationUnavailable))
        }
    }

    /// Normalizes Core Location failures without exposing framework diagnostics to the UI.
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(with: .failure(CoreLocationServiceError.locationUnavailable))
    }

    static func authorization(from status: CLAuthorizationStatus) -> PermissionAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .unavailable
        }
    }

    private func finish(with result: Result<WeatherLocation, any Error>) {
        let continuation = pendingContinuation
        pendingContinuation = nil
        continuation?.resume(with: result)
    }

    private func cancelPendingRequest() {
        manager.stopUpdatingLocation()
        finish(with: .failure(CancellationError()))
    }
}
