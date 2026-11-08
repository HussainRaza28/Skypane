//
//  LocationProvider.swift
//  Skypane
//

import CoreLocation

/// Gets the Mac's approximate location for local weather, asking permission the first time.
final class LocationProvider {
    enum LocationError: Error {
        case denied
        case unavailable
    }

    /// Waits for the next location fix and returns its coordinate.
    /// Starting live updates asks for permission if it hasn't been decided yet.
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location.coordinate
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw LocationError.denied
            }
        }
        throw LocationError.unavailable
    }
}
