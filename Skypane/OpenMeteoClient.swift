//
//  OpenMeteoClient.swift
//  Skypane
//

import Foundation

/// Current conditions at one location, in metric units.
struct WeatherReport: Equatable {
    /// WMO weather interpretation code.
    let weatherCode: Int
    let temperatureCelsius: Double
    /// Precipitation of all kinds, in millimeters per hour.
    let precipitationPerHour: Double
    /// Snowfall, in centimeters per hour.
    let snowfallPerHour: Double
    /// Wind speed at 10 m, in kilometers per hour.
    let windSpeed: Double
    /// Direction the wind is coming from, in degrees clockwise from north.
    let windDirection: Double
    /// Visibility in meters, when the model provides it.
    let visibility: Double?
    let isDay: Bool
    let sunrise: Date?
    let sunset: Date?

    var condition: WeatherCondition { WeatherCondition(code: weatherCode) }
}

/// Fetches current weather from Open-Meteo (free, no API key).
final class OpenMeteoClient {
    enum ClientError: Error {
        case badResponse
    }

    private let forecastEndpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!

    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherReport {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,snowfall,weather_code,wind_speed_10m,wind_direction_10m,is_day,visibility"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let requestURL = components?.url else { throw ClientError.badResponse }

        let (responseData, response) = try await URLSession.shared.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClientError.badResponse
        }

        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: responseData)
        return forecast.makeReport()
    }
}

/// The parts of Open-Meteo's forecast response that Skypane uses.
private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        /// Length of the period that sums like precipitation cover, in seconds.
        let interval: Int?
        let temperature2m: Double?
        let precipitation: Double?
        let snowfall: Double?
        let weatherCode: Int?
        let windSpeed10m: Double?
        let windDirection10m: Double?
        let isDay: Int?
        let visibility: Double?

        // Spelled out because automatic snake-case conversion turns "temperature_2m" into "temperature2M".
        enum CodingKeys: String, CodingKey {
            case interval, precipitation, snowfall, visibility
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let sunrise: [Double]?
        let sunset: [Double]?
    }

    let current: Current
    let daily: Daily?

    func makeReport() -> WeatherReport {
        // Precipitation and snowfall are sums over the interval; scale them to per-hour rates.
        let intervalSeconds = Double(max(current.interval ?? 3600, 1))
        let perHourScale = 3600 / intervalSeconds

        return WeatherReport(
            weatherCode: current.weatherCode ?? 0,
            temperatureCelsius: current.temperature2m ?? 0,
            precipitationPerHour: (current.precipitation ?? 0) * perHourScale,
            snowfallPerHour: (current.snowfall ?? 0) * perHourScale,
            windSpeed: current.windSpeed10m ?? 0,
            windDirection: current.windDirection10m ?? 0,
            visibility: current.visibility,
            isDay: (current.isDay ?? 1) == 1,
            sunrise: daily?.sunrise?.first.map { Date(timeIntervalSince1970: $0) },
            sunset: daily?.sunset?.first.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
