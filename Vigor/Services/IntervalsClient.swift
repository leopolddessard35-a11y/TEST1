import Foundation

/// Accepte un identifiant texte ou numérique.
struct FlexibleString: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            value = ""
        }
    }
}

/// Décode une valeur si son format est celui attendu, sinon l'ignore (sans faire échouer tout le JSON).
struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

/// Intervals.icu : reçoit officiellement tout de Garmin Connect (séances FIT complètes, sommeil, VFC, readiness…).
struct IntervalsClient {
    static let apiKeyAccount = "intervals.apiKey"

    let apiKey: String
    let athleteID: String

    struct Wellness: Decodable {
        let id: String
        let ctl: Double?
        let atl: Double?
        let weight: Double?
        let restingHR: Double?
        let hrv: Double?
        let hrvSDNN: Double?
        let sleepSecs: Double?
        let sleepScore: Double?
        let avgSleepingHR: Double?
        let readiness: Double?
        let spO2: Double?
        let respiration: Double?
        let vo2max: Double?
        let steps: Double?
        let bodyFat: Double?

        enum CodingKeys: String, CodingKey {
            case id, ctl, atl, weight, restingHR, hrv, hrvSDNN, sleepSecs, sleepScore, avgSleepingHR, readiness
            case spO2, respiration, vo2max, steps, bodyFat
        }

        /// Décodage tolérant : un champ mal typé (texte, entier, null) ne fait jamais échouer toute la synchro.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            func number(_ key: CodingKeys) -> Double? {
                if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
                if let text = try? c.decodeIfPresent(String.self, forKey: key) {
                    return Double(text.replacingOccurrences(of: ",", with: "."))
                }
                return nil
            }
            ctl = number(.ctl)
            atl = number(.atl)
            weight = number(.weight)
            restingHR = number(.restingHR)
            hrv = number(.hrv)
            hrvSDNN = number(.hrvSDNN)
            sleepSecs = number(.sleepSecs)
            sleepScore = number(.sleepScore)
            avgSleepingHR = number(.avgSleepingHR)
            readiness = number(.readiness)
            spO2 = number(.spO2)
            respiration = number(.respiration)
            vo2max = number(.vo2max)
            steps = number(.steps)
            bodyFat = number(.bodyFat)
        }
    }

    struct Activity: Decodable {
        let id: FlexibleString
        let startDateLocal: String?
        let type: String?
        let name: String?
        let movingTime: Double?
        let distance: Double?
        let trainingLoad: Double?
        let averageWatts: Double?
        let weightedAverageWatts: Double?
        let averageHeartRate: Double?
        let intensity: Double?
        let calories: Double?
        let hrZoneTimesRaw: Lenient<[Double]>?
        let decouplingRaw: Lenient<Double>?
        let averageCadenceRaw: Lenient<Double>?
        let elevationGainRaw: Lenient<Double>?

        var hrZoneTimes: [Double]? { hrZoneTimesRaw?.value }
        var decoupling: Double? { decouplingRaw?.value }
        var averageCadence: Double? { averageCadenceRaw?.value }
        var elevationGain: Double? { elevationGainRaw?.value }

        enum CodingKeys: String, CodingKey {
            case id, type, name, distance, calories
            case decouplingRaw = "decoupling"
            case startDateLocal = "start_date_local"
            case movingTime = "moving_time"
            case trainingLoad = "icu_training_load"
            case averageWatts = "icu_average_watts"
            case weightedAverageWatts = "icu_weighted_avg_watts"
            case averageHeartRate = "average_heartrate"
            case intensity = "icu_intensity"
            case hrZoneTimesRaw = "icu_hr_zone_times"
            case averageCadenceRaw = "average_cadence"
            case elevationGainRaw = "total_elevation_gain"
        }

        var sport: Sport? {
            switch type ?? "" {
            case "VirtualRide": .indoorCycling
            case "Ride", "GravelRide", "MountainBikeRide", "EBikeRide": .cycling
            case "Run", "TrailRun", "VirtualRun": .running
            case "WeightTraining": nil
            default: .other
            }
        }

        /// Intervals donne l'IF en pourcentage (ex. 72,5).
        var intensityFactor: Double? {
            guard let intensity, intensity > 0 else { return nil }
            return intensity > 3 ? intensity / 100 : intensity
        }
    }

    struct Event: Decodable {
        let id: FlexibleString
        let startDateLocal: String?
        let name: String?
        let description: String?
        let category: String?
        let type: String?
        let movingTime: Double?
        let trainingLoad: Double?

        enum CodingKeys: String, CodingKey {
            case id, name, description, category, type
            case startDateLocal = "start_date_local"
            case movingTime = "moving_time"
            case trainingLoad = "icu_training_load"
        }
    }

    enum IntervalsError: LocalizedError {
        case missingKey, unauthorized, http(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Renseigne ta clé d'API Intervals.icu dans Réglages."
            case .unauthorized: "Clé d'API ou identifiant athlète Intervals.icu incorrect."
            case .http(let code): "Intervals.icu a répondu avec l'erreur \(code)."
            }
        }
    }

    /// Recréés à chaque usage : ils suivent le fuseau horaire actuel (voyage, changement d'heure en cours de route).
    static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static var localDateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }

    static func parseLocal(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = localDateTimeFormatter.date(from: String(raw.prefix(19))) { return date }
        return dayFormatter.date(from: String(raw.prefix(10)))
    }

    func wellness(oldest: Date, newest: Date) async throws -> [Wellness] {
        try await get("wellness", oldest: oldest, newest: newest)
    }

    func activities(oldest: Date, newest: Date) async throws -> [Activity] {
        try await get("activities", oldest: oldest, newest: newest)
    }

    func plannedWorkouts(oldest: Date, newest: Date) async throws -> [Event] {
        try await get("events", oldest: oldest, newest: newest, extra: [URLQueryItem(name: "category", value: "WORKOUT")])
    }

    /// Bien-être brut (toutes les clés renvoyées), pour le diagnostic « Données reçues de Garmin ».
    func wellnessRaw(oldest: Date, newest: Date) async throws -> [[String: Any]] {
        let data = try await fetch("wellness", oldest: oldest, newest: newest)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func get<T: Decodable>(_ path: String, oldest: Date, newest: Date, extra: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await fetch(path, oldest: oldest, newest: newest, extra: extra))
    }

    private func fetch(_ path: String, oldest: Date, newest: Date, extra: [URLQueryItem] = []) async throws -> Data {
        guard !apiKey.isEmpty else { throw IntervalsError.missingKey }
        let athlete = athleteID.trimmingCharacters(in: .whitespaces).isEmpty ? "0" : athleteID.trimmingCharacters(in: .whitespaces)
        var components = URLComponents(string: "https://intervals.icu/api/v1/athlete/\(athlete)/\(path)")!
        components.queryItems = [
            URLQueryItem(name: "oldest", value: Self.dayFormatter.string(from: oldest)),
            URLQueryItem(name: "newest", value: Self.dayFormatter.string(from: newest)),
        ] + extra

        var request = URLRequest(url: components.url!)
        let token = Data("API_KEY:\(apiKey)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw IntervalsError.unauthorized }
            if !(200..<300).contains(http.statusCode) { throw IntervalsError.http(http.statusCode) }
        }
        return data
    }
}
